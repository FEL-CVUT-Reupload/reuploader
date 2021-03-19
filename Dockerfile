FROM ubuntu:latest
RUN apt-get -y update --fix-missing

# fix some TZ issues
ENV TZ 'Europe/Prague'
RUN echo $TZ > /etc/timezone && \
apt-get update && apt-get install -y tzdata && \
rm /etc/localtime && \
ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && \
dpkg-reconfigure -f noninteractive tzdata && \
apt-get clean

# install dependencies
RUN apt-get -y install git wget sudo fzf
RUN apt-get -y install xvfb firefox-geckodriver firefox python3 python3-pip python3-venv
RUN apt-get -y install nodejs npm ffmpeg
RUN apt-get -y install libnss3 libgbm1

# add a non-root user
RUN useradd -m user
#USER user
WORKDIR /src

# install and configure yarn
RUN wget -O - https://dl.yarnpkg.com/debian/pubkey.gpg | apt-key add -
RUN echo "deb https://dl.yarnpkg.com/debian/ stable main" | tee /etc/apt/sources.list.d/yarn.list
RUN apt-get update && apt-get -y install yarn

COPY workspace_package.json package.json
RUN yarn set version berry
RUN yarn plugin import workspace-tools

# install youtube uploader
RUN git clone https://github.com/FEL-CVUT-Reupload/youtube_uploader_selenium.git
RUN pip3 install -r /src/youtube_uploader_selenium/requirements.txt

# install google drive downloader
RUN git clone https://github.com/circulosmeos/gdown.pl.git

# install destreamer
RUN git clone https://github.com/FEL-CVUT-Reupload/destreamer.git
RUN chown -R user:user /src/destreamer

# install sharepoint downloader
RUN git clone https://github.com/FEL-CVUT-Reupload/sharepoint_downloader.git

# install youtube-dl
RUN pip3 install youtube-dl

# install yarn dependencies
RUN yarn install
RUN yarn workspace destreamer tsc

# reuploader script
COPY reuploader.sh reuploader.sh

# CMD ["/usr/bin/bash"]
ENV NODE_EXEC "yarn node"
CMD ["/usr/bin/bash", "reuploader.sh"]
