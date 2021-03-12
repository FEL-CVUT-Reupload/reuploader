#!/usr/bin/env bash
NODE_EXEC=${NODE_EXEC:-"node"}

set -e
export LANG=C.UTF-8

channel="UCzQzKzGlpX4qBi060qdwIug"
cache_path="/mnt"
mkdir -p "$cache_path/destreamer"
mkdir -p "$cache_path/sharepoint"
mkdir -p "$cache_path/uploader"

# start the youtube login background job
# job control is turned off by default in scripts (set +m)
python3 youtube_uploader_selenium/login.py --channel="$channel" --username="a" --password="a" --cookies="$cache_path/uploader" --headless >/dev/null &
YT_LOGIN_PID=$!

while true; do
	echo "Metadata template:"
	types=("přednáška" "cvičení" "seminář" "<custom>")
	template=$(while ! IFS=$'\n' eval 'echo -e "${types[*]}"' | fzf --height=5 --reverse --color=16 --no-info; do true; done)
	echo -e "\e[AVideo template: $template"

	if [[ "$template" == "<custom>" ]]; then
		read -r -p "Video title: " -e video_title
		read -r -p "Video description: " -e video_description
		read -r -p "Playlist: " -e video_playlist
		echo "Video visibility:"
		visibilities=("unlisted" "public" "private")
		video_visibility=$(while ! IFS=$'\n' eval 'echo -e "${visibilities[*]}"' | fzf --height=4 --reverse --color=16 --no-info; do true; done)
		echo -e "\e[AVideo visibility: $video_visibility"
	else
		read -r -p "Subject code: " -e subject
		read -r -p "Lecture number: " -e lecnum
		read -r -p "Date string: " -i "$(date +'%-d. %-m. %Y')" -e datestr
		read -r -p "Semester: " -i "LS 20/21" -e semester
		read -r -p "Lecture title: " -e lectitle
		read -r -p "Video description: " -e video_description

		case "$template" in
			"přednáška")
				category1="přednáška"
				categoryN="přednášky"
				;;
			"cvičení")
				category1="cvičení"
				categoryN="cvičení"
				;;
			"seminář")
				category1="seminář"
				categoryN="semináře"
				;;
			*)
				echo -e "\033[31mUnknown lecture type!\033[0m"
				exit 1
				;;
		esac

		test -n "$lectitle" && lectitle=": $lectitle"
		subject=$(echo "$subject" | tr '[:lower:]' '[:upper:]')
		video_title="$subject $lecnum. $category1 ($datestr)$lectitle"
		video_playlist="$subject $categoryN [$semester]"
		video_visibility="unlisted"
	fi

	echo -e "\033[34m"
	echo "Title: $video_title"
	echo "Description: $video_description"
	echo "Playlist: $video_playlist"
	echo "Visibility: $video_visibility"
	echo -e "\033[0m"

	read -p "Okay? [Y/n] " -n 1 -r
	echo
	if [[ $REPLY =~ ^[YyJj]?$ ]]; then
		break
	fi
	echo
done

if [[ -f "local_video" ]]; then
	source=0
	url="local_video"
else
	echo "Source:"
	sources=(
		# "local file"
		"any video url"
		# "bbb internal player"
		"google drive"
		"microsoft stream (teams)"
		"sharepoint (teams)"
		"youtube video"
		"youtube livestream"
	)
	source=$(while ! IFS=$'\n' eval 'echo -e "${sources[*]}"' | fzf --height=7 --reverse --color=16 --no-info; do true; done)
	echo -e "\e[ASource: $source"

	if [[ "$source" == "youtube livestream" ]]; then
		read -r -p "Recording time: " -i "2h" -e rectime
	fi

	read -r -p "URL/URI: " -e url
	echo
fi

# if there are any jobs...
if [[ "$(jobs -r)" ]]; then
	echo "Logging in to YouTube..."
fi

# wait for the youtube login job (or just get the exit code if it's finished already)
set +e
wait $YT_LOGIN_PID
status=$?
set -e

# run the youtube login again if the background job failed
while true; do
	if [[ "$status" == "7" ]]; then
		read -r -p "ČVUT username: "  -e cvut_username
		read -r -s -p "ČVUT password: "  -e cvut_password
		echo
	else
		break
	fi

	echo "Logging in to YouTube..."
	set +e
	python3 youtube_uploader_selenium/login.py --channel="$channel" --username="$cvut_username" --password="$cvut_password" --cookies="$cache_path/uploader" --headless
	status="$?"
	set -e
done

# not bigger than 1080p, vp9 preferred
ytformat='bestvideo[vcodec^=vp9][height<=1080]+bestaudio/best[vcodec^=vp9][height<=1080]/bestvideo[height<=1080]+bestaudio/best[height<=1080]'

echo
case "$source" in
	"local file")
		tmp_filename="$url"
		;;
	"any video url")
		tmp_filename="video"

		while true; do
			set +e
			wget --http-user="$http_username" --http-password="$http_password" "$url" -O "$tmp_filename"
			status="$?"
			set -e
			if [[ "$status" == "6" ]]; then
				read -r -p "HTTP username: " -e http_username
				read -r -s -p "HTTP password: " -e http_password
				echo
			else
				break
			fi
		done

		tmp_filename=$(readlink -f "$tmp_filename")
		;;
	"bbb internal player")
		echo "bbb-internal is not implemented yet."
		exit 1
		cd bbb-recorder/
		tmp_filename="video.webm"
		node export.js "$url" "$tmp_filename"
		tmp_filename=$(readlink -f "$tmp_filename")
		cd ../
		;;
	"microsoft stream (teams)")
		cd destreamer/

		chown user:user -R "$cache_path/destreamer"

		while true; do
			set +e
			sudo -u user NODE_EXEC="$NODE_EXEC" xvfb-run ./destreamer.sh --outputDirectory "." --format mp4 -x -u "$cvut_username@cvut.cz" -p "$cvut_password" -k -c "$cache_path/destreamer" -i "$url"
			status="$?"
			set -e
			if [[ "$status" == "7" ]]; then
				read -r -p "ČVUT username: "  -e cvut_username
				read -r -s -p "ČVUT password: "  -e cvut_password
				echo
			else
				break
			fi
		done

		tmp_filename=$(ls -t | grep -E "*.mp4$" | head -n1)
		tmp_filename=$(readlink -f "$tmp_filename")

		cd ../
		;;
	"youtube video")
		# tmp_filename=$(youtube-dl -f "$ytformat" --get-filename "$url" -o "video.%(ext)s")
		youtube-dl --fragment-retries infinite -f "$ytformat" "$url" -o "video.%(ext)s"
		tmp_filename=$(ls -t | grep -E "video.*$" | head -n1)
		tmp_filename=$(readlink -f "$tmp_filename")
		;;
	"youtube livestream")
		tmp_filename=$(youtube-dl -f "$ytformat" --get-filename "$url" -o "video.%(ext)s")

		set -m # SIGINT is ignored when job control is disabled!!!
		youtube-dl --fragment-retries infinite -f "$ytformat" "$url" -o "video.%(ext)s" &
		PID=$!
		sleep "$rectime"
		kill -INT $PID
		set +m

		# wait for the youtube-dl to spin down
		sleep 20s

		tmp_filename=$(readlink -f "$tmp_filename")
		;;
	"sharepoint (teams)")
		tmp_filename="sharepoint_downloader/video"

		while true; do
			set +e
			$NODE_EXEC ./sharepoint_downloader/index.js -u "$cvut_username" -p "$cvut_password" --chromeData "$cache_path/sharepoint" -i "$url" -o "$tmp_filename"
			status="$?"
			set -e
			if [[ "$status" == "7" ]]; then
				read -r -p "ČVUT username: "  -e cvut_username
				read -r -s -p "ČVUT password: "  -e cvut_password
				echo
			else
				break
			fi
		done

		tmp_filename=$(readlink -f "$tmp_filename")
		;;
	"google drive")
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
python3 youtube_uploader_selenium/upload.py \
	--video="$tmp_filename" \
	--channel="$channel" \
	--title="$video_title" \
	--description="$video_description" \
	--playlist="$video_playlist" \
	--privacy="$video_visibility" \
	--cookies="$cache_path/uploader" \
	--headless

echo -e "\n\033[32mDONE\033[0m"
