/***************************************************************************
  This file is part of Project Apollo - NASSP
  Copyright 2025

  Autosave Handling (Header)

  Project Apollo is free software; you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation; either version 2 of the License, or
  (at your option) any later version.

  Project Apollo is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with Project Apollo; if not, write to the Free Software
  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

  See http://nassp.sourceforge.net/license/ for more details.

  **************************************************************************/

#pragma once

#include <OrbiterAPI.h>
#include <string>

namespace nassp
{
	///
	/// Writes the running scenario to Scenarios/Autosave/<mission>/ at a fixed real-time
	/// interval while the owning vessel has focus. One instance is owned by each vessel
	/// that supports autosaving; settings are read from that vessel's launchpad config
	/// file through ProcessConfigFileLine().
	///
	/// \ingroup InternalSystems
	///
	class Autosave
	{
	public:
		Autosave();

		///
		/// \brief Attach the autosave to its vessel. Call before the first Timestep().
		///
		void Init(VESSEL *v);

		///
		/// \brief Handle one line of the launchpad config file.
		/// \return true if the line was an autosave setting.
		///
		bool ProcessConfigFileLine(char *line);

		///
		/// \brief Save the scenario if the interval has elapsed. Call from clbkPreStep().
		///
		void Timestep(double missionTime, const std::string &missionName);

	protected:
		void DoSave(double missionTime, const std::string &missionName);
		void FormatGET(char *str, double missionTime);
		void GetScenarioDirectory(char *dir);
		void UpdateNotification();
		void ShowNotification(char *text);

		VESSEL *vessel;

		bool enabled;
		int intervalMinutes;
		bool notificationEnabled;

		///
		/// The interval is measured in real time, and only while the owning vessel has
		/// focus, so that switching between the CSM and the LM doesn't trigger a save
		/// on every change.
		///
		bool hasFocus;
		double elapsedSeconds;
		double lastSysTime;

		NOTEHANDLE hNote;
		double notificationEndTime;
	};
}
