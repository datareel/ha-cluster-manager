// ------------------------------- //
// -------- Start of File -------- //
// ------------------------------- //
// ----------------------------------------------------------- //
// C++ Header File
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

Node standby for the Datareel cluster manager.

An operator puts a node in standby with:

  drcm_server --client --command=standby [--force]

The node stops its own resources and any it runs as a backup, then
tells its peers it is in standby in its keep alive replies. The peers
take over its resources at once, without waiting for dead_node_count
missed keep alives. The state is kept in standby_file, so the node
stays in standby across a restart or reboot until:

  drcm_server --client --command=unstandby

The node then waits until the peers have stopped their backup copies
of its resources before it starts them again, so the resources never
run on two nodes at once.
*/
// ----------------------------------------------------------- //
#ifndef __DRCM_STANDBY_HPP__
#define __DRCM_STANDBY_HPP__

#include "gxdlcode.h"
#include "drcm_server.h"
#include "m_crypto.h"

// Longest time an unstandby waits for the peers to stop their backup
// copies of this node's resources before starting them anyway
const int CM_FAILBACK_WAIT_SECS = 180;

// Longest time the standby and unstandby client commands wait for the
// resources to move
const int CM_CLIENT_STANDBY_WAIT_SECS = 300;

// A standby request must be this fresh (frame timestamp), so an old
// captured request cannot be replayed after a restart
const int CM_STANDBY_REQUEST_MAX_AGE = 300;

// Server side
// Read standby_file at start up. Returns 1 if this node starts in standby.
int cm_standby_load();

// Returns this node's CM_PEER_STATE_* value, and the keep alive reply
// payload for it ("state:active", "state:releasing" or "state:standby").
int cm_node_state();
const char *cm_node_state_payload();

// Resource threads call this each pass while fenced, with released = 1
// once their resources are stopped. Peers are told about the standby
// after all resource threads have released.
void cm_standby_thread_released(int res_thread, int released);

// In standby the floating IPs and file systems are released after the
// crontabs, services and applications, so nothing still uses them.
// Returns 1 when res_thread may release its resources.
int cm_standby_may_release(int res_thread);

// Handle a STANDBY or UNSTANDBY request frame from client_name. Fills
// reply with a message for the client and returns CM_CMD_ACK or
// CM_CMD_NAK.
int cm_handle_standby_request(const CMFrame &f, const char *client_name, gxString &reply);

// Read the CM_PEER_STATE_* value from an authenticated keep alive or
// ping reply
int cm_reply_peer_state(const CMFrame &reply);

// Held by each resource thread. After an unstandby, hold() returns 1
// while a peer still runs one of this node's resources as a backup
// (its stats list the resource, such as "backup_ip:web"), up to
// CM_FAILBACK_WAIT_SECS.
struct CMFailbackWait {
  CMFailbackWait();
  int hold(int res_thread, const gxList<gxString> &own_resources);

  int prev_standby;
  int waiting;
  time_t wait_until;
  int logged;
};

// Client side commands. Return 0 on success.
int cm_client_standby(int force);
int cm_client_unstandby();

#endif // __DRCM_STANDBY_HPP__
// ----------------------------------------------------------- //
// ------------------------------- //
// --------- End of File --------- //
// ------------------------------- //
