#!/bin/bash

# Define the directory where recordings will be saved
recording_dir="/home/$USER/Videos/wl-screenrec"

# Function to handle recording start or stop
record_or_stop() {
	# Check if the recording directory exists; create it if not
	if [[ ! -d $recording_dir ]]; then
		mkdir -p "$recording_dir" || { echo "Error: Failed to create the directory $recording_dir"; exit 1; }
	fi
	
	# Check if recording should start or stop
	if [[ $SWAYNC_TOGGLE_STATE == true ]]; then
		# Start recording
		local filename
		filename="$recording_dir/wl-screenrec-$(date +'%Y-%m-%d-%H-%M-%S').mp4"
		notify-send -a recorder "Video recording started with wl-screenrec 📹"
		echo "<NOTICE> $(date +"%Y-%m-%d %H:%M:%S"): Video recording started with wl-screenrec - $filename"

		wl-screenrec --codec hevc --audio --audio-device alsa_output.pci-0000_00_1f.3.analog-stereo.monitor --filename "$filename"
	else
		# Stop recording
		local pid
		pid=$(pidof wl-screenrec)
		
		if [[ -n $pid ]]; then
			# Send SIGINT signal to stop wl-screenrec
			echo "Sending Ctrl + C signal to wl-screenrec with PID $pid"
			kill -SIGINT "$pid"
			
			# Get the most recent recording file
			local filename
			# shellcheck disable=SC2012 # we know the contents of the directory are safe
			filename=$(ls -t "$recording_dir" | head -n1)
			echo "Video recording ended and saved to $filename"
			notify-send -a recorder "Video recording ended and saved to: $recording_dir/$filename 📹"
		else
			echo "wl-screenrec is not running."
		fi
	fi
}

# Call the function to start or stop recording
record_or_stop