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
RUN apt-get -y install git wget sudo
RUN apt-get -y install xvfb firefox-geckodriver firefox python3 python3-pip python3-venv
RUN apt-get -y install nodejs npm ffmpeg
RUN apt-get -y install libnss3 libgbm1

# add a non-root user
RUN useradd -m user
#USER user
WORKDIR /src

# install youtube uploader
RUN git clone https://github.com/FEL-CVUT-Reupload/youtube_uploader_selenium.git
RUN pip3 install -r /src/youtube_uploader_selenium/requirements.txt

# install destreamer
RUN git clone https://github.com/FEL-CVUT-Reupload/destreamer.git
WORKDIR /src/destreamer
RUN npm install
RUN npm run build
WORKDIR /src
RUN chown -R user:user /src/destreamer

# install sharepoint downloader
RUN git clone https://github.com/FEL-CVUT-Reupload/sharepoint_downloader.git
WORKDIR /src/sharepoint_downloader
RUN npm install
WORKDIR /src

# reuploader script
COPY reuploader.sh reuploader.sh

# CMD ["/usr/bin/bash"]
CMD ["/usr/bin/bash", "reuploader.sh"]
