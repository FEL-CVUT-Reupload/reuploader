#!/usr/bin/env bash
NODE_EXEC=${NODE_EXEC:-"node"}

set -e
export LANG=C.UTF-8

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
echo "  6. sharepoint (teams)"
read -p "Source: " -e source
read -p "URL/URI: " -e url


if [[ "$source" == "6" ]] || [[ ! -f cookies/youtube.com.pkl ]]; then
	login=true
fi

if [[ "$source" == "3" ]] && test "$(find cookies/.token_cache -mmin +60 2>/dev/null)"; then
	login=true
fi

if [[ -n "$login" ]]; then
	read -p "ČVUT username: " -e username
	read -s -p "ČVUT password: " -e password
fi

if [[ "$source" == "5" ]]; then
	read -p "Recording time: " -i "2h" -e rectime
fi


test -n "$lectitle" && lectitle=": $lectitle"

echo
echo -e "\033[34m"
echo "Title: $subject $lecnum. $category1 ($datestr)$lectitle"
echo "Description: $description"
echo "Playlist: $subject $categoryN [$semester]"
echo -e "\033[0m"


# not bigger than 1080p, vp9 preferred
ytformat='bestvideo[vcodec^=vp9][height<=1080]+bestaudio/best[vcodec^=vp9][height<=1080]/bestvideo[height<=1080]+bestaudio/best[height<=1080]'

case $source in
	0) # local file
		tmp_filename="$url"
	;;
	1) # any video url
		tmp_filename="video"
		wget "$url" -O "$tmp_filename"
		tmp_filename=$(readlink -f "$tmp_filename")
	;;
	2) # bbb-internal
		echo "bbb-internal is not implemented yet."
		exit 1
		cd bbb-recorder/
		tmp_filename="video.webm"
		node export.js "$url" "$tmp_filename"
		tmp_filename=$(readlink -f "$tmp_filename")
		cd ../
	;;
	3) # microsoft stream (teams)
		if [[ -f cookies/.token_cache ]]; then
			cp -v cookies/.token_cache destreamer/
			chown user:user destreamer/.token_cache
		fi
		cd destreamer/
		sudo -u user NODE_EXEC="$NODE_EXEC" xvfb-run ./destreamer.sh --outputDirectory "." --format mp4 -x -k -u "$username@cvut.cz" -p "$password" -i "$url"
		tmp_filename=$(ls -t | grep -E "*.mp4$" | head -n1)
		tmp_filename=$(readlink -f "$tmp_filename")
		cd ../
		cp -uv destreamer/.token_cache cookies/.token_cache
	;;
	4) # youtube static
		# tmp_filename=$(youtube-dl -f "$ytformat" --get-filename "$url" -o "video.%(ext)s")
		youtube-dl --fragment-retries infinite -f "$ytformat" "$url" -o "video.%(ext)s"
		tmp_filename=$(ls -t | grep -E "video.*$" | head -n1)
		tmp_filename=$(readlink -f "$tmp_filename")
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

		tmp_filename=$(readlink -f "$tmp_filename")
	;;
	6) # sharepoint
		tmp_filename="sharepoint_downloader/video"
		$NODE_EXEC ./sharepoint_downloader/index.js -u "$username" -p "$password" -i "$url" -o "$tmp_filename"
		tmp_filename=$(readlink -f "$tmp_filename")
	;;
	7) # google drive
		tmp_filename="video"
		./gdown.pl/gdown.pl "$url" "$tmp_filename"
		tmp_filename=$(readlink -f "$tmp_filename")
	;;
	*)
		echo -e "\033[31mUnknown video source!\033[0m"
		exit 1
	;;
esac


# upload
[[ -z "$login" ]] && cp -v cookies/youtube.com.pkl youtube_uploader_selenium/
cd youtube_uploader_selenium/
python3 upload.py \
	--video="$tmp_filename" \
	--channel="UCzQzKzGlpX4qBi060qdwIug" \
	--title="$subject $lecnum. $category1 ($datestr)$lectitle" \
	--description="$description" \
	--playlist="$subject $categoryN [$semester]" \
	--privacy="unlisted" \
	--username="$username" \
	--password="$password" \
	--headless

[[ -f youtube.com.pkl ]] && cp -uv youtube.com.pkl ../cookies/

echo -e "\n\033[32mDONE\033[0m"

