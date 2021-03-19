#!/usr/bin/env bash

semester_default="LS 20/21"
channel="UCzQzKzGlpX4qBi060qdwIug"
cache_path="/mnt"

NODE_EXEC=${NODE_EXEC:-"node"}

set -e
trap "stty sane" EXIT
export LANG=C.UTF-8

mkdir -p "$cache_path/destreamer"
mkdir -p "$cache_path/sharepoint"
mkdir -p "$cache_path/uploader"

# start the youtube login background job
# job control is turned off by default in scripts (set +m)
python3 youtube_uploader_selenium/login.py --channel="$channel" --username="a" --password="a" --cookies="$cache_path/uploader" --headless >/dev/null &
YT_LOGIN_PID=$!

function sel() {
	prompt="$1"
	echo "$prompt" >&2
	options=("${@:2}")
	len="${#options[@]}"

	set -e
	selection="$(while true; do
		IFS=$'\n' eval 'echo -e "${options[*]}"' | fzf --height="$((len + 1))" --reverse --color=16 --no-info
		case "$?" in
			0) break ;;
			1) continue ;;
			*) exit "$?" ;;
		esac
	done)"

	echo -e "\e[A$prompt $selection" >&2
	echo "$selection"
}

while true; do
	template=$(sel "Metadata template:" "přednáška" "cvičení" "seminář" "konzultace" "<custom>")

	if [[ "$template" == "<custom>" ]]; then
		read -er -p "Video title: " video_title
		read -er -p "Video description: " video_description
		read -er -p "Playlist: " video_playlist
		video_visibility=$(sel "Video visibility:" "unlisted" "public" "private")
	else
		read -er -p "Subject code: " subject
		read -er -p "Lecture number: " lecnum
		read -er -p "Date string: " -i "$(date +'%-d. %-m. %Y')" datestr
		read -er -p "Semester: " -i "$semester_default" semester
		read -er -p "Lecture title: " lectitle
		read -er -p "Video description: " video_description

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
			"konzultace")
				category1="konzultace"
				categoryN="konzultace"
				;;
			*)
				echo -e "\033[31mUnknown lecture template!\033[0m"
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

	read -r -n 1 -p "Okay? [Y/n] "
	echo
	if [[ $REPLY =~ ^[YyJj]?$ ]]; then
		break
	fi
	echo
done

if [[ -f "local_video" ]]; then
	source="local file"
	url="local_video"
else
	source=$(
		sel "Source:" \
			"any video url" \
			"google drive" \
			"microsoft stream (teams)" \
			"sharepoint (teams)" \
			"youtube-dl" \
			"youtube-dl (livestream)"
	)

	if [[ "$source" == "youtube-dl (livestream)" ]]; then
		read -r -p "Recording time: " -i "2h" -e rectime
	fi

	read -er -p "URL/URI: " url
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
		read -er -p "ČVUT username: " cvut_username
		read -ers -p "ČVUT password: " cvut_password
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
				read -er -p "HTTP username: " http_username
				read -ers -p "HTTP password: " http_password
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
				read -er -p "ČVUT username: " cvut_username
				read -ers -p "ČVUT password: " cvut_password
				echo
			else
				break
			fi
		done

		tmp_filename=$(ls -t | grep -E "*.mp4$" | head -n1)
		tmp_filename=$(readlink -f "$tmp_filename")

		cd ../
		;;
	"youtube-dl")
		youtube-dl --fragment-retries infinite "$url" -o "video.%(ext)s"
		tmp_filename=$(ls -t | grep -E "video.*$" | head -n1)
		tmp_filename=$(readlink -f "$tmp_filename")
		;;
	"youtube-dl (livestream)")
		tmp_filename=$(youtube-dl --get-filename "$url" -o "video.%(ext)s")

		set -m # SIGINT is ignored when job control is disabled!!!
		youtube-dl --fragment-retries infinite "$url" -o "video.%(ext)s" &
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
				read -er -p "ČVUT username: " cvut_username
				read -ers -p "ČVUT password: " cvut_password
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
echo
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
