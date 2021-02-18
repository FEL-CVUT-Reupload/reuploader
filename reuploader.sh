#!/usr/bin/env bash
set -e

read -p "Subject code: " -e subject
subject=$(echo "$subject" | tr '[:lower:]' '[:upper:]')

read -p "Lecture number: " -e lecnum
read -p "Lecture type (p|c): " -e code

case "$code" in 
	"p") 
		category1="přednáška"
		categoryN="přednášky"
	;;
	"c") 
		category1="cvičení"
		categoryN="cvičení"
	;;
	*) 
		echo -e "\033[31mUnknown lecture type!\033[0m"
		exit 1
	;;
esac

read -p "Date string: " -i "$(date +'%-d. %-m. %Y')" -e datestr
read -p "Semester: " -i "LS 20/21" -e semester
read -p "Lecture title: " -e lectitle
read -p "Video description: " -e description
echo
echo "Available sources:" 
echo "  0. local file"
echo "  1. any video url"
echo "  2. bbb internal player"
echo "  3. microsoft stream (teams)"
echo "  4. youtube video"
echo "  5. youtube livestream"
read -p "Source: " -e source
read -p "URL/URI: " -e url

case $source in
	3) # microsoft stream (teams)
		read -p "ČVUT username: " -e username
		read -p "ČVUT password: " -e password
	;;
	5) # youtube livestream
		read -p "Recording time: " -i "2h" -e rectime
	;;
esac


echo





# not bigger than 1080p, vp9 preferred
ytformat='bestvideo[vcodec^=vp9][height<=1080]+bestaudio/best[vcodec^=vp9][height<=1080]/bestvideo[height<=1080]+bestaudio/best[height<=1080]'

case $source in
	0) # local file
		tmp_filename="$url"
	;;
	1) # any video url
		tmp_filename="video.${url##*.}"
		wget "$url" -O "$tmp_filename"
	;;
	2) # bbb-internal
		echo "bbb-internal is not implemented yet."
		exit 1
		cd bbb-recorder/
		tmp_filename="video.webm"
		node export.js "$url" "$tmp_filename"
	;;
	3) # microsoft stream (teams)
		cd destreamer/
		xvfb-run ./destreamer.sh --outputDirectory "." --format mp4 -x -k -u "$username@cvut.cz" -p "$password" -i "$url"
		tmp_filename=$(ls -t | grep -E "*.mp4$" | head -n1)
	;;
	4) # youtube static
		# tmp_filename=$(youtube-dl -f "$ytformat" --get-filename "$url" -o "video.%(ext)s")
		youtube-dl --fragment-retries infinite -f "$ytformat" "$url" -o "video.%(ext)s"
		tmp_filename=$(ls -t | grep -E "video.*$" | head -n1)
	;;
	5) # youtube livestream
		tmp_filename=$(youtube-dl -f "$ytformat" --get-filename "$url" -o "video.%(ext)s")
		
		set -m  # SIGINT is ignored when job control is disabled!!!
		youtube-dl --fragment-retries infinite -f "$ytformat" "$url" -o "video.%(ext)s" &
		PID=$!
		sleep "$rectime"
		kill -INT $PID
		set +m
		
		# wait for the youtube-dl to spin down
		sleep 20s
	;;
	*)
		echo -e "\033[31mUnknown video source!\033[0m"
		exit 1
	;;
esac




test -n "$lectitle" && lectitle=": $lectitle"

echo "Title: $subject $lecnum. $category1 ($datestr)$lectitle"
echo "Description: $description"
echo "Playlist: $subject $categoryN $YEAR"




exit 99
youtube-upload --title="$subject $lecnum. $category1 ($datestr)$lectitle" --description="$description" --playlist="$subject $categoryN [$semester]" --category="Education" --privacy=unlisted --default-language="cs" --default-audio-language="cs" "$filename"

echo -e "\n\033[32mDONE\033[0m"

