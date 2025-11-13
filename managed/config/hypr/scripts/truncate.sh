#!/usr/bin/env bash

# Function to truncate song name intelligently
truncate_song_name() {
	song_name="$1"
	max_length=17

	# Remove "(feat." or "(ft." and everything that follows it using regex
	song_name=$(echo "$song_name" | sed -E 's/\s*\(\s*(feat\.|ft\.)[^\)]*\)//')

	# If the song name is shorter than the max length, return it as is
	if [ ${#song_name} -le $max_length ]; then
		echo "$song_name"
		return
	fi

	# Split the song name into words
	IFS=" " read -r -a words <<< "$song_name"
	truncated=""

	# Truncate based on the max length
	for word in "${words[@]}"; do
		# Add word if it fits within the max length
		if [ ${#truncated} -eq 0 ]; then
			new_truncated="$word"
		else
			new_truncated="$truncated $word"
		fi

		# Check if the new truncated length is still under the max length
		if [ ${#new_truncated} -le $max_length ]; then
			truncated="$new_truncated"
		else
			break
		fi
	done

	# Add ellipsis if truncation occurred
	if [ ${#truncated} -lt ${#song_name} ]; then
		truncated="$truncated..."
	fi

	echo "$truncated"
}

# Check if an argument (song name) is provided
if [ $# -eq 0 ]; then
	echo "Usage: $0 <song_name>"
	exit 1
fi

# Call the function with the provided argument
truncate_song_name "$1"
