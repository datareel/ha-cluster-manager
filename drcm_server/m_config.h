// ------------------------------- //
// -------- Start of File -------- //
// ------------------------------- //
// ----------------------------------------------------------- //
// C++ Header File
// C++ Compiler Used: GNU, Intel
// Produced By: DataReel Software Development Team
// File Creation Date: 07/17/2016
// Date Last Modified: 12/30/2023
// Copyright (c) 2016-2024 DataReel Software Development
// ----------------------------------------------------------- // 
// ---------- Include File Description and Details  ---------- // 
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

Program config funcions for Datareel cluster manager.

*/
// ----------------------------------------------------------- //   
#ifndef __DRCM_CONFIG_HPP__
#define __DRCM_CONFIG_HPP__

#include "gxdlcode.h"
#include "drcm_server.h"

struct CMcrontabs {
  CMcrontabs() { }
  ~CMcrontabs() { }
  CMcrontabs(const CMcrontabs &n) { Copy(n); }
  CMcrontabs operator=(const CMcrontabs &n) {
    Copy(n);
    return *this;
  }

  void Copy(const CMcrontabs &n) {
    if(&n == this) return;
    nickname = n.nickname;
    template_file = n.template_file;
    install_location = n.install_location;
    resource_script = n.resource_script;
  }

  gxString nickname;
  gxString template_file;
  gxString install_location;
  gxString resource_script;
};

struct CMipaddrs {
  CMipaddrs() { }
  ~CMipaddrs() { }
  CMipaddrs(const CMipaddrs &n) { Copy(n); }
  CMipaddrs operator=(const CMipaddrs &n) {
    Copy(n);
    return *this;
  }

  void Copy(const CMipaddrs &n) {
    if(&n == this) return;
    nickname = n.nickname;
    ip_address = n.ip_address;
    netmask = n.netmask;
    interface = n.interface;
    resource_script = n.resource_script;
  }

  gxString nickname;
  gxString ip_address;
  gxString netmask;
  gxString interface;
  gxString resource_script;
};

struct CMservices {
  CMservices() { }
  ~CMservices() { }
  CMservices(const CMservices &n) { Copy(n); }
  CMservices operator=(const CMservices &n) {
    Copy(n);
    return *this;
  }

  void Copy(const CMservices &n) {
    if(&n == this) return;
    nickname = n.nickname;
    service_name = n.service_name;
    resource_script = n.resource_script;
  }

  gxString nickname;
  gxString service_name;
  gxString resource_script;
};

struct CMapplications {
  CMapplications() { }
  ~CMapplications() { }
  CMapplications(const CMapplications &n) { Copy(n); }
  CMapplications operator=(const CMapplications &n) {
    Copy(n);
    return *this;
  }

  void Copy(const CMapplications &n) {
    if(&n == this) return;
    nickname = n.nickname;
    user = n.user;
    group = n.group;
    start_program = n.start_program;
    stop_program = n.stop_program;
    ensure_script = n.ensure_script;
  }

  gxString nickname;
  gxString user;
  gxString group;
  gxString start_program;
  gxString stop_program;
  gxString ensure_script;
};

struct CMfilesystems {
  CMfilesystems() { }
  ~CMfilesystems() { }
  CMfilesystems(const CMfilesystems &n) { Copy(n); }
  CMfilesystems operator=(const CMfilesystems &n) {
    Copy(n);
    return *this;
  }

  void Copy(const CMfilesystems &n) {
    if(&n == this) return;
    nickname = n.nickname;
    source = n.source;
    target = n.target;
    resource_script = n.resource_script;
  }

  gxString nickname;
  gxString source;
  gxString target;
  gxString resource_script;
};

struct CMnode {
  CMnode();
  ~CMnode() { }
  
  CMnode(const CMnode &n) { Copy(n); }
  CMnode operator=(const CMnode &n) {
    Copy(n);
    return *this;
  }

  int CLUSTER_TAKE_OVER_FLAG(int set = 0, int unset = 0);
  void Copy(const CMnode &n);
  void copy_list(const gxList<gxString> &source, gxList<gxString> &dest);

  gxString nodename;
  gxString hostname;
  gxString keep_alive_ip;
  int crontabs_check;
  int services_check;
  int applications_check;
  int ipaddrs_check;
  int filesystems_check;
  int keep_services;
  int keep_filesystems;
  int keep_applications;
  gxList<gxString> crontabs; 
  gxList<gxString> backup_crontabs; 
  gxList<gxString> floating_ip_addrs; 
  gxList<gxString> backup_floating_ip_addrs;  
  gxList<gxString> services; 
  gxList<gxString> backup_services; 
  gxList<gxString> applications; 
  gxList<gxString> backup_applications; 
  gxList<gxString> filesystems;
  gxList<gxString> backup_filesystems;
  CMnode *active_ptr;
  int node_is_active;

  // TCP/cloud mode (Phase 4). Optional per node.
  gxList<gxString> peer_endpoints;   // one or more host:port keep-alive paths
  gxString tls_peer_fingerprint;     // optional SHA-256 cert pin for this peer
  gxString floating_ip_provider;     // cloud provider hook, e.g. "aws"

  // State this peer reported in its last keep alive reply (see
  // CM_PEER_STATE_*). A 1.42 or older node sends no state.
  volatile int peer_state;

private:
  int cluster_take_over_flag;
  gxMutex cluster_take_over_flag_lock;
  int cluster_take_over_flag_is_locked;
};

// Node info for detailed status reports
struct CMstatsnode {
  CMstatsnode() {
    is_alive = 0;
  }
  ~CMstatsnode() { }
  CMstatsnode(const CMstatsnode &n) { Copy(n); }
  CMstatsnode operator=(const CMstatsnode &n) {
    Copy(n);
    return *this;
  }
  void Copy(const CMstatsnode &n);

  CMnode node;
  int is_alive;
  gxList<gxString> stats;
};

// Node state carried in keep alive and ping replies (CMnode::peer_state)
const int CM_PEER_STATE_UNKNOWN = 0;  // no state in the reply (DRCM 1.42 or older)
const int CM_PEER_STATE_ACTIVE = 1;   // running its resources normally
const int CM_PEER_STATE_RELEASING = 2; // standby requested, still stopping resources
const int CM_PEER_STATE_STANDBY = 3;  // in standby, all resources stopped

// Resource threads, used to index CMconfig::standby_released
const int CM_RES_CRONTABS = 0;
const int CM_RES_IPADDRS = 1;
const int CM_RES_SERVICES = 2;
const int CM_RES_APPLICATIONS = 3;
const int CM_RES_FILESYSTEMS = 4;
const int CM_NUM_RES_THREADS = 5;

// Cluster transport selection (servercfg->cluster_transport)
const int CM_TRANSPORT_UDP = 0; // UDP keep alive, same-subnet clusters (default)
const int CM_TRANSPORT_TCP = 1; // TCP + TLS, internet / cloud clusters

struct CMconfig {
  CMconfig(); 
  ~CMconfig();

  int QUEUE_NODE_COUNT();
  int QUEUE_DEBUG_COUNT();
  int QUEUE_PROC_COUNT();

  CMstats stats;
  gxList<CMnode *> nodes;
  gxList<CMcrontabs> node_crontabs;
  gxList<CMipaddrs> node_ipaddrs;
  gxList<CMservices> node_services;
  gxList<CMapplications> node_applications;
  gxList<CMfilesystems> node_filesystems;
  int num_resource_crons;
  int num_resource_ipaddrs;
  int num_resource_services;
  int num_resource_applications;
  int num_resource_filesystems;
  int is_client;
  int is_client_interactive;
  int client_ping_count; // Client ping count
  gxString client_ping_nodename; // Ping and rstats node name
  gxString client_command;
  int debug;
  int debug_level;
  int verbose;
  int verbose_level;
  gxString config_file;
  int user_config_file;
  int check_config;
  gxsPort_t udpport;
  gxsPort_t tcpport;
  int dead_node_count;

  // Transport and TCP/TLS mode (Phase 4). cluster_transport selects the
  // wire transport: 0 = UDP (default, LAN), 1 = TCP+TLS (internet/cloud).
  int cluster_transport;          // CM_TRANSPORT_UDP or CM_TRANSPORT_TCP
  gxString tls_ca_file;           // cluster CA used to verify peers
  gxString tls_cert_file;         // this node's certificate
  gxString tls_key_file;          // this node's private key
  int tls_min_version;            // 2 for TLS 1.2 (default), 3 for TLS 1.3
  int replay_window_secs;         // timestamp window; 0 = seq-only (default)
  gxString witness_endpoint;      // optional quorum witness host:port
  int quorum_required;            // 1 = need witness agreement before takeover

  // Split brain protection for WAN clusters. isolation_check is a script
  // that exits 0 if this node can still reach the outside world (for
  // example the internet). When every peer stops answering and the script
  // fails, this node is the isolated side: it stops its own resources and
  // will not take over the peers' resources. takeover_check is a script
  // run with the dead peer's nodename before a takeover; a non-zero exit
  // means the peer is still alive by some other path, so do not fail over.
  gxString isolation_check;       // script path, empty = disabled (default)
  int isolation_check_count;      // missed keep alives before running it
  int isolation_recover_secs;     // isolated node resumes after the check passes this long
  gxString takeover_check;        // script path, empty = disabled (default)
  volatile int node_isolated;     // 1 = this node stood down its resources

  // Standby: an operator asked this node to release its resources so
  // the peers take them over (drcm_server --client --command=standby).
  // The state survives a restart through standby_file. Peers are told
  // only after every resource thread has stopped its resources.
  gxString standby_file;          // default /var/lib/drcm/standby
  volatile int node_standby;      // 1 = standby requested
  volatile int standby_released[CM_NUM_RES_THREADS]; // 1 = thread stopped its resources
  volatile int resource_wake;     // bumped when a take over flag changes
  volatile time_t standby_until;  // timed standby (--time) end, 0 = until unstandby
  int my_node_index;              // position of this node in the config, staggers takeovers
  int client_force;               // --force for the standby client command
  long client_standby_secs;       // --time for the standby client command, 0 = none

  gxString my_hostname;
  gxString run_dir, log_dir, spool_dir;
  gxString etc_dir;
  int accept_clients;
  int server_retry;
  int fatal_error;
  gxString service_name;
  gxString client_name;
  gxString ProgramName;
  int echo_loop;
  gxString cluster_user;
  gxString cluster_group;
  gxString cluster_umask;
  gxString sudo_command;

  // Server stop and restart variables
  int kill_server;
  int restart_server;
  int process_loop;
  gxMutex process_lock;
  gxCondition process_cond;
  gxThread_t *process_thread;
  gxThread_t *log_thread;
  gxThread_t *udp_server_thread;
  gxThread_t *keep_alive_thread;
  gxThread_t *tcp_server_thread;
  gxThread_t *crontab_thread;
  gxThread_t *services_thread;
  gxThread_t *applications_thread;
  gxThread_t *ipaddr_thread;
  gxThread_t *filesystems_thread;
  thrPool *client_request_pool;
  gxThread_t *console_thread;

  // -- arg overrides when CFG file loaded
  int has_debug_override;
  int has_debug_level_override;
  int has_verbose_override;
  int has_verbose_level_override;
  int has_config_file_override;
  int has_log_file_name_override;
  int has_log_level_override;
  int has_log_file_clear_override;
  int has_enable_logging_override;

  // Log settings
  LogFile logfile;
  int clear_log;
  int enable_logging;
  int num_logs_to_keep;
  long max_log_size;
  int last_log;
  gxString logfile_name;
  int log_level;
  int log_file_err;
  int bind_to_keep_alive_ip;

  // Log queue
  int log_queue_size;
  int log_queue_debug_size;
  int log_queue_proc_size;
  LogQueueNode *loq_queue_nodes;
  LogQueueNode *loq_queue_debug_nodes;
  LogQueueNode *loq_queue_proc_nodes;

  // Server hash and auth key
  char auth_key[2048];
  char sha1sum[40];
  gxString auth_key_file;
  gxString sha1_file;

private:  // Cannot be accessed directly
  int queue_node_count;
  int queue_debug_count;
  int queue_proc_count;

private: // Internal thread vars
  gxMutex queue_node_count_lock;
  int queue_node_count_is_locked;
  gxMutex queue_debug_count_lock;
  int queue_debug_count_is_locked;
  gxMutex queue_proc_count_lock;
  int queue_proc_count_is_locked;
};

// Config functions
int LoadOrBuildConfigFile();

int ProcessArgs(int argc, char *argv[]);
int ProcessDashDashArg(gxString &arg);

// Non-thread safe check DIR function uses when program starts
// Return 1 if DIR exists or 0 if DIR doesn't exist or can be created
int NT_check_dir(const gxString &dir);

extern CMconfig ServerConfigSruct;
extern CMconfig *servercfg;

#endif // __DRCM_CONFIG_HPP__
// ----------------------------------------------------------- // 
// ------------------------------- //
// --------- End of File --------- //
// ------------------------------- //
