#!/usr/bin/env bash
set -e

YEAR=2020
#YEAR="$(date +%Y)"


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
read -p "Description: " -e description
echo
echo "Available sources:" 
echo "  0. local file"
echo "  1. any video url"
echo "  2. bbb internal player"
echo "  3. microsoft stream"
echo "  4. youtube livestream"
echo "  5. youtube static"
read -p "Source: " -e source
read -p "URL/URI: " -e url
echo


directory="/home/$USER/Videos/FEL/$subject/$code"
mkdir -p "$directory"

# default extension (will be changed)
extension="mp4"

# not bigger than 1080p, vp9 preferred
ytformat='bestvideo[vcodec^=vp9][height<=1080]+bestaudio/best[vcodec^=vp9][height<=1080]/bestvideo[height<=1080]+bestaudio/best[height<=1080]'

# purpose: assign extension and tmp_filename, get the video on tmp_filename
case $source in
	0) # local file
		extension="${url##*.}"
		tmp_filename="$url"
	;;
	1) # any video url
		extension="${url##*.}"
		tmp_filename="video.$extension"
		wget "$url" -O "$tmp_filename"
	;;
	2) # bbb-internal		
		cd bbb-recorder/
		extension="webm"
		tmp_filename="video.$extension"
		node export.js "$url" "$tmp_filename"
	;;
	3) # microsoft stream (teams)
		cd destreamer/
		./destreamer.sh --outputDirectory "." --format mp4 -x -k -u "telkaond@cvut.cz" -i "$url"
		extension="mp4"
		tmp_filename=$(ls -t | grep -E "*.mp4$" | head -n1)
	;;
	4) # youtube livestream
		read -p "Recording time: " -i "2h" -e rectime
		
		tmp_filename=$(youtube-dl -f "$ytformat" --get-filename "$url" -o "video.%(ext)s")
		extension="${tmp_filename##*.}"
		
		set -m  # SIGINT is ignored when job control is disabled!
		youtube-dl -f "$ytformat" "$url" -o "video.%(ext)s" &
		PID=$!
		sleep "$rectime"
		kill -INT $PID
		set +m
		
		# wait for the youtube-dl to spin down
		sleep 20s
	;;
	5) # youtube static
		# tmp_filename=$(youtube-dl -f "$ytformat" --get-filename "$url" -o "video.%(ext)s")
		# extension="${tmp_filename##*.}"
		youtube-dl -f "$ytformat" "$url" -o "video.%(ext)s"
		tmp_filename=$(ls -t | grep -E "video.*$" | head -n1)
		extension="${tmp_filename##*.}"
		
	;;
	*)
		echo -e "\033[31mUnknown video source!\033[0m"
		exit 1
	;;
esac


subject_lower=$(echo "$subject" | tr '[:upper:]' '[:lower:]')
rev_datestr=$(echo "$datestr" | tr ' .' '\n' | tac | xargs | tr ' ' '_')
filename="${directory}/${subject_lower}_${code}${lecnum}_${rev_datestr}.${extension}"

echo
echo "target: $filename"
mv -v "$tmp_filename" "$filename"
echo


echo "Title: $subject $lecnum. $category1 ($datestr)"
echo "Description: $description"
echo "Playlist: $subject $categoryN $YEAR"
echo "Filename: $filename"

#exit 99
youtube-upload --title="$subject $lecnum. $category1 ($datestr)" --description="$description" --playlist="$subject $categoryN $YEAR" --category="Education" --privacy=unlisted --default-language="cs" --default-audio-language="cs" "$filename"

echo -e "\n\033[32mDONE\033[0m"

