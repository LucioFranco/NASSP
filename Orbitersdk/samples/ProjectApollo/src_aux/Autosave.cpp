/***************************************************************************
  This file is part of Project Apollo - NASSP
  Copyright 2025

  Autosave Handling

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

#include "Orbitersdk.h"

#include "Autosave.h"

#include <direct.h>
#include <math.h>
#include <stdio.h>
#include <string.h>

namespace nassp
{
	//
	// Autosaves live in their own folder below Orbiter's scenario directory, so that
	// they don't clutter the mission scenarios in the launchpad browser.
	//
	static const char *AUTOSAVE_FOLDER = "Autosave";

	//
	// Orbiter's own default, see the ScenarioDir entry in Orbiter.cfg.
	//
	static const char *DEFAULT_SCENARIO_DIR = "Scenarios\\";

	static const double NOTIFICATION_DURATION = 3.0;

	Autosave::Autosave()

	{
		vessel = NULL;

		enabled = false;
		intervalMinutes = 10;
		notificationEnabled = true;

		hasFocus = false;
		elapsedSeconds = 0.0;
		lastSysTime = 0.0;

		hNote = NULL;
		notificationEndTime = 0.0;
	}

	void Autosave::Init(VESSEL *v)

	{
		vessel = v;
	}

	bool Autosave::ProcessConfigFileLine(char *line)

	{
		int i;

		if (!strnicmp(line, "AUTOSAVE_ENABLED", 16)) {
			sscanf(line + 16, "%i", &i);
			enabled = (i != 0);
			return true;
		}
		else if (!strnicmp(line, "AUTOSAVE_INTERVAL", 17)) {
			sscanf(line + 17, "%i", &intervalMinutes);
			if (intervalMinutes < 1) { intervalMinutes = 1; }	// Be paranoid
			if (intervalMinutes > 60) { intervalMinutes = 60; }
			return true;
		}
		else if (!strnicmp(line, "AUTOSAVE_NOTIFICATION", 21)) {
			sscanf(line + 21, "%i", &i);
			notificationEnabled = (i != 0);
			return true;
		}

		return false;
	}

	void Autosave::Timestep(double missionTime, const std::string &missionName)

	{
		if (!enabled || !vessel) return;

		//
		// Expire the notification whether or not we still have focus, otherwise it
		// stays on screen when the user switches to another vessel right after a save.
		//
		UpdateNotification();

		if (oapiGetFocusObject() != vessel->GetHandle()) {
			hasFocus = false;
			return;
		}

		double sysTime = oapiGetSysTime();

		if (!hasFocus) {
			hasFocus = true;
			lastSysTime = sysTime;
			return;
		}

		elapsedSeconds += sysTime - lastSysTime;
		lastSysTime = sysTime;

		if (elapsedSeconds < (double) intervalMinutes * 60.0) return;

		elapsedSeconds = 0.0;
		DoSave(missionTime, missionName);
	}

	void Autosave::DoSave(double missionTime, const std::string &missionName)

	{
		std::string folderName = missionName.empty() ? vessel->GetName() : missionName;

		char getStr[32];
		FormatGET(getStr, missionTime);

		//
		// oapiSaveScenario() won't create directories, so do it here. The path has to be
		// built from Orbiter's scenario directory, which the user can redirect.
		//
		char scenarioDir[256], dir[512];

		GetScenarioDirectory(scenarioDir);

		sprintf(dir, "%s%s", scenarioDir, AUTOSAVE_FOLDER);
		_mkdir(dir);
		sprintf(dir, "%s%s\\%s", scenarioDir, AUTOSAVE_FOLDER, folderName.c_str());
		_mkdir(dir);

		char path[512], description[256];

		sprintf(path, "%s\\%s\\%s", AUTOSAVE_FOLDER, folderName.c_str(), getStr);

		if (missionName.empty()) {
			sprintf(description, "NASSP Autosave");
		} else {
			sprintf(description, "NASSP Autosave - %s", missionName.c_str());
		}

		if (!oapiSaveScenario(path, description)) {
			char buffer[1024];

			sprintf(buffer, "(Autosave) ERROR: Can't write scenario %s", path);
			oapiWriteLog(buffer);
			return;
		}

		if (notificationEnabled) {
			char buffer[512];

			sprintf(buffer, "Autosaved: %s/%s", folderName.c_str(), getStr);
			ShowNotification(buffer);
		}
	}

	void Autosave::FormatGET(char *str, double missionTime)

	{
		int totalSeconds = (int) fabs(missionTime);
		int hours = totalSeconds / 3600;
		int minutes = (totalSeconds % 3600) / 60;
		int seconds = totalSeconds % 60;

		//
		// MissionTime runs negative before liftoff, and the shipped scenarios start as
		// early as T-27h. Tag those as T- rather than letting a minus sign break each
		// of the individual fields.
		//
		sprintf(str, "GET-%s%03d.%02d.%02d", (missionTime < 0.0) ? "T-" : "", hours, minutes, seconds);
	}

	void Autosave::GetScenarioDirectory(char *dir)

	{
		strcpy(dir, DEFAULT_SCENARIO_DIR);

		FILEHANDLE hFile = oapiOpenFile("Orbiter.cfg", FILE_IN_ZEROONFAIL, ROOT);
		if (!hFile) return;

		char *line;

		while (oapiReadScenario_nextline(hFile, line)) {
			if (strnicmp(line, "ScenarioDir", 11)) continue;

			char buffer[256];
			strncpy(buffer, line, 255);
			buffer[255] = '\0';

			// Cut comments, then take everything past the '='.
			char *comment = strchr(buffer, ';');
			if (comment) *comment = '\0';

			char *value = strchr(buffer, '=');
			if (!value) continue;

			value++;
			while (*value == ' ' || *value == '\t') value++;
			if (!*value) continue;

			strcpy(dir, value);
			if (dir[strlen(dir) - 1] != '\\') strcat(dir, "\\");
			break;
		}

		oapiCloseFile(hFile, FILE_IN_ZEROONFAIL);
	}

	void Autosave::UpdateNotification()

	{
		if (!hNote || notificationEndTime <= 0.0) return;
		if (oapiGetSysTime() < notificationEndTime) return;

		char blank[] = "";

		oapiAnnotationSetText(hNote, blank);
		notificationEndTime = 0.0;
	}

	void Autosave::ShowNotification(char *text)

	{
		if (!hNote) {
			hNote = oapiCreateAnnotation(false, 0.65, _V(0.0, 1.0, 0.5));
			oapiAnnotationSetPos(hNote, 0.02, 0.15, 0.4, 0.2);
		}

		oapiAnnotationSetText(hNote, text);
		notificationEndTime = oapiGetSysTime() + NOTIFICATION_DURATION;
	}
}
