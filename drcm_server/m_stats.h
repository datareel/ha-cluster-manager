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

Stat functions for Datareel cluster manager.

*/
// ----------------------------------------------------------- //   
#ifndef __DRCM_STATS_HPP__
#define __DRCM_STATS_HPP__

#include "gxdlcode.h"
#include "drcm_server.h"

// Stats message queue
struct CMstats {
  CMstats() {
    stats_is_locked = 0;
    stats_retries = 3;
  }

  int Add(gxString &s, int check_existing = 0);
  int Remove(const gxString &s);
  void Clear();
  void Get(gxList<gxString> &s);
  void Get(gxString &sbuf);

private:
  gxList<gxString> stats;
  gxMutex stats_lock;
  gxCondition stats_cond;
  int stats_is_locked;
  int stats_retries;
};

#endif // __DRCM_STATS_HPP__
// ----------------------------------------------------------- // 
// ------------------------------- //
// --------- End of File --------- //
// ------------------------------- //
