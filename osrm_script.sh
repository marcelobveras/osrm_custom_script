#!/bin/bash         
	
map_url=https://download.geofabrik.de/south-america/brazil-latest.osm.pbf
map_file=brazil-latest.osm.pbf
git_osrm=https://github.com/Project-OSRM/osrm-backend.git
osrm_folder=osrm-backend
# map_file=/home/marcelobveras/Documents/perceptron2.png
cd /tmp

date_file=$(date -r $map_file +%s)
date_now=$(date +%s)

date_diff=$(($date_now - $date_file)) 
date_diff=$((date_diff / 2592000))
if (( $date_diff > 0 )); then
	wget $map_url
	touch $map_file
fi

git clone $git_osrm

mv $map_file $osrm_folder

cd $osrm_folder

docker run -t -v "${PWD}:/data" ghcr.io/project-osrm/osrm-backend osrm-extract -p /opt/car.lua /data/$map_file || echo "osrm-extract failed"
