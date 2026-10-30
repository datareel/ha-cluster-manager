// ------------------------------- //
// -------- Start of File -------- //
// ------------------------------- //
// ----------------------------------------------------------- //
// C++ Source Code File
// C++ Compiler Used: GNU, Intel
// Produced By: DataReel Software Development Team
// File Creation Date: 10/29/2026
// Date Last Modified: 10/29/2026
// Copyright (c) 2016-2026 DataReel Software Development
// ----------------------------------------------------------- //
// ------------- Program Description and Details ------------- //
// ----------------------------------------------------------- //
/*
This file is part of the DataReel software distribution.

Datareel is free software: you can redistribute it and/or modify it
under the terms of the GNU General Public License as published by the
Free Software Foundation, either version 3 of the License, or (at your
option) any later version.

Datareel software is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
General Public License for more details.

You should have received a copy of the GNU General Public License
along with the DataReel software distribution.  If not, see
<http://www.gnu.org/licenses/>.

Node standby for the Datareel cluster manager. See m_standby.h.

*/
// ----------------------------------------------------------- //
#include "gxdlcode.h"

#include <errno.h>
#include <stdio.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <sys/stat.h>

#include "drcm_server.h"
#include "m_standby.h"

// Stats names for each resource thread, as used in the stats buffer
// ("cron:nick" for this node's own, "backup_cron:nick" for a backup)
static const char *res_stat_names[CM_NUM_RES_THREADS] = {
  "cron", "ip", "service", "application", "filesystem"
};
static const char *res_display_names[CM_NUM_RES_THREADS] = {
  "crontab", "floating IP", "service", "application", "file system"
};

static gxMutex standby_lock; // Guards standby requests and the stats entry

static const gxList<gxString> &own_resources(CMnode *n, int r)
{
  switch(r) {
    case CM_RES_CRONTABS: return n->crontabs;
    case CM_RES_IPADDRS: return n->floating_ip_addrs;
    case CM_RES_SERVICES: return n->services;
    case CM_RES_APPLICATIONS: return n->applications;
    default: return n->filesystems;
  }
}

static const gxList<gxString> &backup_resources(CMnode *n, int r)
{
  switch(r) {
    case CM_RES_CRONTABS: return n->backup_crontabs;
    case CM_RES_IPADDRS: return n->backup_floating_ip_addrs;
    case CM_RES_SERVICES: return n->backup_services;
    case CM_RES_APPLICATIONS: return n->backup_applications;
    default: return n->backup_filesystems;
  }
}

// Copy a frame payload into a string
static void payload_string(const CMFrame &f, gxString &s)
{
  s.Clear();
  if(f.payload_len == 0 || !f.payload) return;
  char *buf = new char[f.payload_len + 1];
  memcpy(buf, f.payload, f.payload_len);
  buf[f.payload_len] = '\0';
  s = buf;
  delete[] buf;
}

int cm_parse_duration(const char *s, long &secs)
{
  secs = 0;
  if(!s || !*s) return 1;
  long total = 0;
  const char *p = s;
  while(*p) {
    if(*p < '0' || *p > '9') return 1;
    long n = 0;
    while(*p >= '0' && *p <= '9') {
      n = n * 10 + (*p - '0');
      if(n > CM_STANDBY_MAX_SECS) return 1;
      p++;
    }
    long unit;
    switch(*p) {
      case 'd': case 'D': unit = 86400; break;
      case 'h': case 'H': unit = 3600; break;
      case 'm': case 'M': unit = 60; break;
      case 's': case 'S': unit = 1; break;
      default: return 1; // every number needs a unit
    }
    p++;
    total += n * unit;
    if(total > CM_STANDBY_MAX_SECS) return 1;
  }
  if(total <= 0) return 1;
  secs = total;
  return 0;
}

void cm_format_duration(long secs, gxString &out)
{
  out.Clear();
  if(secs < 0) secs = 0;
  long d = secs / 86400, h = (secs % 86400) / 3600, m = (secs % 3600) / 60, sec = secs % 60;
  if(d) out << d << "d";
  if(h) out << h << "h";
  if(m && d == 0) out << m << "m";
  if((sec && d == 0 && h == 0) || out.is_null()) out << sec << "s";
}

static void format_time(time_t t, gxString &out)
{
  char buf[64];
  struct tm tmv;
  localtime_r(&t, &tmv);
  strftime(buf, sizeof(buf), "%b %d %H:%M:%S", &tmv);
  out = buf;
}

static CMnode *this_cm_node()
{
  gxListNode<CMnode *> *ptr = servercfg->nodes.GetHead();
  while(ptr) {
    if(ptr->data->hostname == servercfg->my_hostname) return ptr->data;
    ptr = ptr->next;
  }
  return 0;
}

static int all_threads_released()
{
  for(int i = 0; i < CM_NUM_RES_THREADS; i++) {
    if(!servercfg->standby_released[i]) return 0;
  }
  return 1;
}

int cm_node_state()
{
  if(!servercfg->node_standby) return CM_PEER_STATE_ACTIVE;
  if(!all_threads_released()) return CM_PEER_STATE_RELEASING;
  return CM_PEER_STATE_STANDBY;
}

const char *cm_node_state_payload()
{
  switch(cm_node_state()) {
    case CM_PEER_STATE_RELEASING: return "state:releasing";
    case CM_PEER_STATE_STANDBY: return "state:standby";
    default: return "state:active";
  }
}

int cm_reply_peer_state(const CMFrame &reply)
{
  gxString sbuf;
  payload_string(reply, sbuf);
  if(sbuf == "state:active") return CM_PEER_STATE_ACTIVE;
  if(sbuf == "state:releasing") return CM_PEER_STATE_RELEASING;
  if(sbuf == "state:standby") return CM_PEER_STATE_STANDBY;
  return CM_PEER_STATE_UNKNOWN;
}

// Keep one node:releasing or node:standby line in the stats buffer
// while this node is in standby, so rstats and cm_stat show it
static gxString until_stat; // the node:standby_until=EPOCH line now in the stats

static void update_standby_stats()
{
  gxString releasing = "node:releasing";
  gxString standby = "node:standby";
  int state = cm_node_state();
  if(!until_stat.is_null()) {
    servercfg->stats.Remove(until_stat);
    until_stat.Clear();
  }
  if(state != CM_PEER_STATE_ACTIVE && servercfg->standby_until) {
    until_stat << clear << "node:standby_until=" << (long)servercfg->standby_until;
    servercfg->stats.Add(until_stat, 1);
  }
  if(state == CM_PEER_STATE_ACTIVE) {
    servercfg->stats.Remove(releasing);
    servercfg->stats.Remove(standby);
  }
  else if(state == CM_PEER_STATE_RELEASING) {
    servercfg->stats.Remove(standby);
    servercfg->stats.Add(releasing, 1);
  }
  else {
    servercfg->stats.Remove(releasing);
    servercfg->stats.Add(standby, 1);
  }
}

void cm_standby_thread_released(int res_thread, int released)
{
  if(res_thread < 0 || res_thread >= CM_NUM_RES_THREADS) return;
  if(servercfg->standby_released[res_thread] == released) return;

  standby_lock.MutexLock();
  int was_standby = (cm_node_state() == CM_PEER_STATE_STANDBY);
  servercfg->standby_released[res_thread] = released;
  if(servercfg->node_standby) {
    update_standby_stats();
    if(!was_standby && cm_node_state() == CM_PEER_STATE_STANDBY) {
      LogMessage("This node released all its resources and is in standby, peers will take them over");
    }
  }
  standby_lock.MutexUnlock();
}

int cm_standby_may_release(int res_thread)
{
  if(res_thread != CM_RES_IPADDRS && res_thread != CM_RES_FILESYSTEMS) return 1;
  return servercfg->standby_released[CM_RES_CRONTABS] &&
    servercfg->standby_released[CM_RES_SERVICES] &&
    servercfg->standby_released[CM_RES_APPLICATIONS];
}

static int write_standby_file(gxString &err)
{
  gxString dir = servercfg->standby_file;
  dir.DeleteAfterLastIncluding("/");
  if(!dir.is_null() && !futils_exists(dir.c_str())) {
    if(mkdir(dir.c_str(), 0755) != 0 && errno != EEXIST) {
      err << clear << "cannot create " << dir << ": " << strerror(errno);
      return 1;
    }
  }

  FILE *fp = fopen(servercfg->standby_file.c_str(), "w");
  if(!fp) {
    err << clear << "cannot write " << servercfg->standby_file << ": " << strerror(errno);
    return 1;
  }
  SysTime logtime;
  fprintf(fp, "standby requested %s\n", logtime.GetSyslogTime());
  fprintf(fp, "Run drcm_server --client --command=unstandby to return this node to service\n");
  if(servercfg->standby_until) {
    gxString when;
    format_time(servercfg->standby_until, when);
    fprintf(fp, "# Timed standby, this node returns to service at %s\n", when.c_str());
    fprintf(fp, "until=%ld\n", (long)servercfg->standby_until);
  }
  if(fclose(fp) != 0) {
    err << clear << "cannot write " << servercfg->standby_file << ": " << strerror(errno);
    return 1;
  }
  return 0;
}

int cm_standby_load()
{
  if(!futils_exists(servercfg->standby_file.c_str())) return 0;

  // A timed standby keeps its end time across a restart
  time_t until = 0;
  FILE *fp = fopen(servercfg->standby_file.c_str(), "r");
  if(fp) {
    char line[256];
    long v;
    while(fgets(line, sizeof(line), fp)) {
      if(sscanf(line, "until=%ld", &v) == 1 && v > 0) until = (time_t)v;
    }
    fclose(fp);
  }

  standby_lock.MutexLock();
  for(int i = 0; i < CM_NUM_RES_THREADS; i++) servercfg->standby_released[i] = 0;
  servercfg->standby_until = until;
  servercfg->node_standby = 1;
  update_standby_stats();
  standby_lock.MutexUnlock();

  gxString message;
  if(until) {
    gxString when;
    format_time(until, when);
    message << clear << "Starting in standby, " << servercfg->standby_file
	    << " exists. Timed standby, this node returns to service at " << when;
  }
  else {
    message << clear << "Starting in standby, " << servercfg->standby_file
	    << " exists. This node will not run any resources until drcm_server --client --command=unstandby";
  }
  LogMessage(message.c_str());
  return 1;
}

// A standby request may only come from this host. In a tunnel setup a
// peer's frames can also arrive from a loopback address, so the request
// must also name this host. Any holder of the cluster key is trusted,
// as for every other cluster message.
static int request_is_local(const char *client_name)
{
  gxString client = client_name;
  if(client.Find("127.") == 0) return 1;
  CMnode *me = this_cm_node();
  if(me && me->keep_alive_ip == client) return 1;
  return 0;
}

// End standby: remove the standby file and clear the state. The
// resource threads then start this node's resources once the peers
// have stopped their backup copies. Called with standby_lock held.
static int leave_standby(const char *reason, gxString &reply)
{
  gxString message;
  if(unlink(servercfg->standby_file.c_str()) != 0 && errno != ENOENT) {
    reply << clear << "ERROR - still in standby, cannot remove " << servercfg->standby_file
	  << ": " << strerror(errno);
    message << clear << "ERROR - " << reason << ", but cannot remove " << servercfg->standby_file
	    << ", staying in standby";
    LogMessage(message.c_str());
    return 1;
  }
  servercfg->node_standby = 0;
  servercfg->standby_until = 0;
  for(int i = 0; i < CM_NUM_RES_THREADS; i++) servercfg->standby_released[i] = 0;
  update_standby_stats();
  reply << clear << "OK - standby ended, this node will start its resources once the peers release them";
  message << clear << reason << ", this node will start its resources once the peers release them";
  LogMessage(message.c_str());
  return 0;
}

int cm_handle_standby_request(const CMFrame &f, const char *client_name, gxString &reply)
{
  gxString message;
  int standby = (f.command == CM_CMD_STANDBY);
  const char *what = standby ? "standby" : "unstandby";

  if(!request_is_local(client_name)) {
    reply << clear << "ERROR - " << what << " requests are only accepted from this host";
    message << clear << "WARNING - Rejected " << what << " request from " << client_name;
    LogMessage(message.c_str());
    return CM_CMD_NAK;
  }

  // Payload: this node's hostname, then for a timed standby (1.46) a
  // second line time=SECONDS. Older servers compare the whole payload
  // with their hostname, so they refuse a timed request.
  gxString payload, hostname, time_arg;
  payload_string(f, payload);
  hostname = payload;
  long secs = 0;
  if(payload.Find("\n") != -1) {
    hostname.DeleteAfterIncluding("\n");
    time_arg = payload;
    time_arg.DeleteBeforeIncluding("\n");
  }
  if(hostname != servercfg->my_hostname) {
    reply << clear << "ERROR - " << what << " request is for " << hostname
	  << ", this node is " << servercfg->my_hostname;
    message << clear << "WARNING - Rejected " << what << " request for " << hostname << " from " << client_name;
    LogMessage(message.c_str());
    return CM_CMD_NAK;
  }
  if(!time_arg.is_null()) {
    gxString v = time_arg;
    if(standby && v.Find("time=") == 0) {
      v.DeleteBeforeIncluding("time=");
      secs = v.Atol();
    }
    if(secs <= 0 || secs > CM_STANDBY_MAX_SECS) {
      reply << clear << "ERROR - bad standby time, the limit is " << CM_STANDBY_MAX_TEXT;
      return CM_CMD_NAK;
    }
  }

  // Refuse an old request even when replay_window_secs is off. The
  // client runs on this host, so the clocks agree.
  time_t now = time(0);
  if(!(f.flags & CM_FLAG_HAS_TIMESTAMP) ||
     (uint64_t)now + CM_STANDBY_REQUEST_MAX_AGE < f.timestamp ||
     f.timestamp + CM_STANDBY_REQUEST_MAX_AGE < (uint64_t)now) {
    reply << clear << "ERROR - " << what << " request is too old or from the future";
    message << clear << "WARNING - Rejected stale " << what << " request from " << client_name;
    LogMessage(message.c_str());
    return CM_CMD_NAK;
  }

  standby_lock.MutexLock();
  int rv = CM_CMD_ACK;
  if(standby) {
    time_t prev_until = servercfg->standby_until;
    int was_standby = servercfg->node_standby;
    servercfg->standby_until = secs ? now + secs : 0;
    gxString err, when, left;
    if(was_standby && !secs && !prev_until) {
      reply << clear << "OK - this node is already in standby";
    }
    else if(write_standby_file(err) != 0) {
      servercfg->standby_until = prev_until;
      reply << clear << "ERROR - " << (was_standby ? "standby time not changed, " : "not entering standby, ") << err;
      message << clear << "ERROR - Standby request failed, " << err;
      LogMessage(message.c_str());
      rv = CM_CMD_NAK;
    }
    else {
      if(!was_standby) {
	for(int i = 0; i < CM_NUM_RES_THREADS; i++) servercfg->standby_released[i] = 0;
	servercfg->node_standby = 1;
      }
      update_standby_stats();
      if(secs) {
	format_time(servercfg->standby_until, when);
	cm_format_duration(secs, left);
      }
      if(!was_standby) {
	if(secs) {
	  reply << clear << "OK - standby started until " << when << " (" << left << "), this node is stopping its resources";
	  message << clear << "Standby requested until " << when << ", stopping all resources on this node so peers can take them over";
	}
	else {
	  reply << clear << "OK - standby started, this node is stopping its resources";
	  message << clear << "Standby requested, stopping all resources on this node so peers can take them over";
	}
      }
      else if(secs) {
	reply << clear << "OK - already in standby, it now ends at " << when << " (" << left << ")";
	message << clear << "Standby time changed, this node returns to service at " << when;
      }
      else {
	reply << clear << "OK - already in standby, the time limit is removed";
	message << clear << "Standby time limit removed, this node stays in standby until unstandby";
      }
      LogMessage(message.c_str());
    }
  }
  else {
    if(!servercfg->node_standby) {
      reply << clear << "OK - this node is not in standby";
    }
    else if(leave_standby("Unstandby requested", reply) != 0) {
      rv = CM_CMD_NAK;
    }
  }
  standby_lock.MutexUnlock();
  return rv;
}

void cm_standby_check_timer()
{
  if(!servercfg->node_standby || !servercfg->standby_until) return;
  if(time(0) < servercfg->standby_until) return;
  standby_lock.MutexLock();
  if(servercfg->node_standby && servercfg->standby_until && time(0) >= servercfg->standby_until) {
    gxString reply;
    leave_standby("Standby time ended", reply);
  }
  standby_lock.MutexUnlock();
}

CMFailbackWait::CMFailbackWait()
{
  prev_standby = servercfg->node_standby;
  waiting = 0;
  wait_until = 0;
  logged = 0;
}

int CMFailbackWait::hold(int res_thread, const gxList<gxString> &own_resources)
{
  gxString message;
  time_t now = time(0);
  int standby = servercfg->node_standby;
  if(prev_standby && !standby) {
    waiting = 1;
    logged = 0;
    wait_until = now + CM_FAILBACK_WAIT_SECS;
  }
  prev_standby = standby;
  if(!waiting) return 0;
  if(!own_resources.GetHead()) {
    waiting = 0;
    return 0;
  }
  if(now >= wait_until) {
    message << clear << "WARNING - Peers did not release this node's " << res_display_names[res_thread]
	    << " resources in " << CM_FAILBACK_WAIT_SECS << " seconds, starting them anyway";
    LogMessage(message.c_str());
    waiting = 0;
    return 0;
  }

  gxString stats_buffer, error_message, stat_name, nickname;
  gxListNode<CMnode *> *ptr = servercfg->nodes.GetHead();
  while(ptr) {
    if(ptr->data->hostname == servercfg->my_hostname || !ptr->data->node_is_active) {
      ptr = ptr->next;
      continue;
    }
    // A peer that cannot be reached cannot be asked, the same as at
    // start up
    if(get_node_stat_buffer(ptr->data, stats_buffer, error_message) == 0) {
      gxListNode<gxString> *rptr = own_resources.GetHead();
      while(rptr) {
	nickname = rptr->data;
	nickname.FilterChar(' ');
	stat_name << clear << "backup_" << res_stat_names[res_thread] << ":" << nickname;
	if(stats_buffer_has(stats_buffer, stat_name)) {
	  if(!logged) {
	    message << clear << "Waiting for " << ptr->data->nodename << " to stop its backup copy of "
		    << res_display_names[res_thread] << " " << nickname << " before starting it";
	    LogMessage(message.c_str());
	    logged = 1;
	  }
	  return 1;
	}
	rptr = rptr->next;
      }
    }
    ptr = ptr->next;
  }

  if(logged) {
    message << clear << "Peers released this node's " << res_display_names[res_thread] << " resources, starting them";
    LogMessage(message.c_str());
  }
  waiting = 0;
  return 0;
}

// ----------------------------------------------------------- //
// Client side
// ----------------------------------------------------------- //

static time_t client_start_time;

static long elapsed()
{
  return (long)(time(0) - client_start_time);
}

// Ask a node for its state with an authenticated ping. Returns a
// CM_PEER_STATE_* value, or -1 if the node did not answer.
static int client_node_state(CMnode *node)
{
  unsigned char rxbuf[CM_RX_BUF_SIZE];
  int bytes_read = 0;
  if(cm_node_exchange(node, CM_CMD_PING, 0, 0, rxbuf, sizeof(rxbuf),
		      &bytes_read, 5, 0) != 0 || bytes_read <= 0) {
    return -1;
  }
  CMFrame reply;
  if(cm_parse_frame(rxbuf, bytes_read, reply) != CM_FRAME_OK || reply.command != CM_CMD_ACK) {
    return -1;
  }
  return cm_reply_peer_state(reply);
}

static const char *state_name(int state)
{
  switch(state) {
    case CM_PEER_STATE_ACTIVE: return "active";
    case CM_PEER_STATE_RELEASING: return "releasing its resources for standby";
    case CM_PEER_STATE_STANDBY: return "in standby";
    case CM_PEER_STATE_UNKNOWN: return "up, but its DRCM version has no standby support";
    default: return "not answering";
  }
}

// Send a STANDBY or UNSTANDBY request to this node's server
static int client_send_request(CMnode *me, int cmd, long secs = 0)
{
  unsigned char rxbuf[CM_RX_BUF_SIZE];
  int bytes_read = 0;
  const char *what = (cmd == CM_CMD_STANDBY) ? "standby" : "unstandby";
  gxString payload = servercfg->my_hostname;
  if(secs > 0) payload << "\n" << "time=" << secs;
  if(cm_node_exchange(me, cmd, payload.c_str(), (int)payload.length(),
		      rxbuf, sizeof(rxbuf), &bytes_read, 10, 0) != 0 || bytes_read <= 0) {
    cout << "ERROR - No reply to the " << what << " request from the DRCM server on this node ("
	 << me->keep_alive_ip.c_str() << "). Is drcm_server 1.43 or later running?" << "\n" << flush;
    return 1;
  }
  CMFrame reply;
  if(cm_parse_frame(rxbuf, bytes_read, reply) != CM_FRAME_OK) {
    cout << "ERROR - Bad or unauthenticated reply to the " << what << " request" << "\n" << flush;
    return 1;
  }
  gxString text;
  payload_string(reply, text);
  cout << text.c_str() << "\n" << flush;
  if(reply.command != CM_CMD_ACK && secs > 0 && text.Find("request is for") != -1) {
    // A 1.43 or 1.44 server compares the whole payload with its hostname
    cout << "The DRCM server on this node is older than 1.46 and has no --time, nothing was changed" << "\n" << flush;
  }
  return reply.command == CM_CMD_ACK ? 0 : 1;
}

// One of this node's resources and the stats line that shows it running
struct CMclientResource {
  gxString display;  // "application app1"
  gxString stat;     // "backup_application:app1" or "application:app1"
  int seen;
};

int cm_client_standby(int force, long secs)
{
  CMnode *me = this_cm_node();
  if(!me) {
    cout << "ERROR - This host " << servercfg->my_hostname.c_str() << " is not a node in the CM config" << "\n" << flush;
    return 1;
  }

  // The peers must be able to take over, or the resources would stop
  // and run nowhere
  cout << "Checking the cluster peers" << "\n" << flush;
  gxList<CMnode *> takeover_peers;
  gxListNode<CMnode *> *ptr = servercfg->nodes.GetHead();
  while(ptr) {
    if(ptr->data == me) {
      ptr = ptr->next;
      continue;
    }
    if(!ptr->data->node_is_active) {
      cout << "  " << ptr->data->nodename.c_str() << ": marked inactive in the CM config" << "\n" << flush;
      ptr = ptr->next;
      continue;
    }
    int state = client_node_state(ptr->data);
    cout << "  " << ptr->data->nodename.c_str() << ": " << state_name(state) << "\n" << flush;
    if(state == CM_PEER_STATE_ACTIVE) takeover_peers.Add(ptr->data);
    ptr = ptr->next;
  }

  // Which of this node's resources a peer that can take over backs up
  gxList<CMclientResource> moving;
  gxList<gxString> not_moving;
  for(int r = 0; r < CM_NUM_RES_THREADS; r++) {
    gxListNode<gxString> *rptr = own_resources(me, r).GetHead();
    while(rptr) {
      gxString nickname = rptr->data;
      nickname.FilterChar(' ');
      gxString backup_entry;
      backup_entry << clear << me->nodename << ":" << nickname;
      int backed_up = 0;
      gxListNode<CMnode *> *pptr = takeover_peers.GetHead();
      while(pptr && !backed_up) {
	gxListNode<gxString> *bptr = backup_resources(pptr->data, r).GetHead();
	while(bptr) {
	  gxString entry = bptr->data;
	  entry.FilterChar(' ');
	  if(entry == backup_entry) {
	    backed_up = 1;
	    break;
	  }
	  bptr = bptr->next;
	}
	pptr = pptr->next;
      }
      gxString display;
      display << clear << res_display_names[r] << " " << nickname;
      if(backed_up) {
	CMclientResource res;
	res.display = display;
	res.stat << clear << "backup_" << res_stat_names[r] << ":" << nickname;
	res.seen = 0;
	moving.Add(res);
      }
      else {
	not_moving.Add(display);
      }
      rptr = rptr->next;
    }
  }

  // Refuse when nothing would take over: no peer with standby support
  // answers, or none of them backs up any of this node's resources
  if(!takeover_peers.GetHead() || (!moving.GetHead() && not_moving.GetHead())) {
    if(!force) {
      if(!takeover_peers.GetHead()) {
	cout << "ERROR - No active peer that supports standby is answering, so nothing could take over" << "\n";
      }
      else {
	cout << "ERROR - No answering peer backs up any of this node's resources, so nothing could take over" << "\n";
      }
      cout << "this node's resources. Not entering standby. Use --force to stop them anyway." << "\n" << flush;
      return 1;
    }
    cout << "WARNING - No peer can take over, --force given, this node's resources will stop" << "\n" << flush;
  }
  if(not_moving.GetHead()) {
    cout << "WARNING - No answering peer backs up these resources, they will stop until unstandby:" << "\n";
    gxListNode<gxString> *nptr = not_moving.GetHead();
    while(nptr) {
      cout << "  " << nptr->data.c_str() << "\n";
      nptr = nptr->next;
    }
    cout << flush;
  }

  client_start_time = time(0);
  if(client_send_request(me, CM_CMD_STANDBY, secs) != 0) return 1;

  // Wait until this node has stopped everything and told its peers
  gxString stats_buffer, error_message;
  gxString standby_stat = "node:standby";
  int released = 0;
  while(elapsed() < CM_CLIENT_STANDBY_WAIT_SECS) {
    if(get_node_stat_buffer(me, stats_buffer, error_message) == 0 &&
       stats_buffer_has(stats_buffer, standby_stat)) {
      released = 1;
      break;
    }
    sSleep(1);
  }
  if(!released) {
    cout << "ERROR - This node did not release its resources in " << CM_CLIENT_STANDBY_WAIT_SECS
	 << " seconds, see the DRCM log. It stays in standby." << "\n" << flush;
    return 1;
  }
  cout << "This node stopped its resources after " << elapsed() << " seconds and is in standby" << "\n" << flush;

  // Wait for the peers to start them
  int num_left = 0;
  gxListNode<CMclientResource> *mptr = moving.GetHead();
  while(mptr) {
    num_left++;
    mptr = mptr->next;
  }
  while(num_left > 0 && elapsed() < CM_CLIENT_STANDBY_WAIT_SECS) {
    gxListNode<CMnode *> *pptr = takeover_peers.GetHead();
    while(pptr) {
      if(get_node_stat_buffer(pptr->data, stats_buffer, error_message) == 0) {
	mptr = moving.GetHead();
	while(mptr) {
	  if(!mptr->data.seen && stats_buffer_has(stats_buffer, mptr->data.stat)) {
	    mptr->data.seen = 1;
	    num_left--;
	    cout << "  " << mptr->data.display.c_str() << " started on " << pptr->data->nodename.c_str()
		 << " after " << elapsed() << " seconds" << "\n" << flush;
	  }
	  mptr = mptr->next;
	}
      }
      pptr = pptr->next;
    }
    if(num_left > 0) sSleep(1);
  }
  if(num_left > 0) {
    cout << "WARNING - " << num_left << " resources were not started on a peer in "
	 << CM_CLIENT_STANDBY_WAIT_SECS << " seconds, check cm_stat and the peers' DRCM logs" << "\n" << flush;
    return 1;
  }
  cout << "Standby complete" << "\n" << flush;
  if(secs > 0) {
    gxString when, left;
    format_time(time(0) - elapsed() + secs, when);
    cm_format_duration(secs, left);
    cout << "This node returns to service by itself at " << when.c_str() << " (" << left.c_str()
	 << " after the request), or run --command=unstandby sooner" << "\n" << flush;
  }
  return 0;
}

int cm_client_unstandby()
{
  CMnode *me = this_cm_node();
  if(!me) {
    cout << "ERROR - This host " << servercfg->my_hostname.c_str() << " is not a node in the CM config" << "\n" << flush;
    return 1;
  }

  gxList<CMclientResource> own;
  int num_left = 0;
  for(int r = 0; r < CM_NUM_RES_THREADS; r++) {
    gxListNode<gxString> *rptr = own_resources(me, r).GetHead();
    while(rptr) {
      gxString nickname = rptr->data;
      nickname.FilterChar(' ');
      CMclientResource res;
      res.display << clear << res_display_names[r] << " " << nickname;
      res.stat << clear << res_stat_names[r] << ":" << nickname;
      res.seen = 0;
      own.Add(res);
      num_left++;
      rptr = rptr->next;
    }
  }

  client_start_time = time(0);
  if(client_send_request(me, CM_CMD_UNSTANDBY) != 0) return 1;

  // The node starts each resource once no peer runs a backup copy of it
  gxString stats_buffer, error_message;
  while(num_left > 0 && elapsed() < CM_CLIENT_STANDBY_WAIT_SECS) {
    if(get_node_stat_buffer(me, stats_buffer, error_message) == 0) {
      gxListNode<CMclientResource> *optr = own.GetHead();
      while(optr) {
	if(!optr->data.seen && stats_buffer_has(stats_buffer, optr->data.stat)) {
	  optr->data.seen = 1;
	  num_left--;
	  cout << "  " << optr->data.display.c_str() << " started on this node after "
	       << elapsed() << " seconds" << "\n" << flush;
	}
	optr = optr->next;
      }
    }
    if(num_left > 0) sSleep(1);
  }
  if(num_left > 0) {
    cout << "WARNING - " << num_left << " resources did not start on this node in "
	 << CM_CLIENT_STANDBY_WAIT_SECS << " seconds, check cm_stat and the DRCM log" << "\n" << flush;
    return 1;
  }
  cout << "Unstandby complete, this node runs its resources again" << "\n" << flush;
  return 0;
}
// ----------------------------------------------------------- //
// ------------------------------- //
// --------- End of File --------- //
// ------------------------------- //
