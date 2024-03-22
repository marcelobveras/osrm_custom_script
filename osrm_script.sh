#!/bin/bash
	
map_url="https://download.geofabrik.de/south-america/brazil-latest.osm.pbf"
map_file="brazil-latest.osm.pbf"
custom_lua_script="https://raw.githubusercontent.com/marcelobveras/osrm_custom_script/main/custom.lua"
lua_script_file="custom.lua"
git_osrm="https://github.com/Project-OSRM/osrm-backend.git"
osrm_folder="osrm-backend"
image_name="ghcr.io/project-osrm/osrm-backend"
update_map=false
container_prod_name="osrm-backend-prod"
container_tmp_name="osrm-backend-tmp"
container_prod_port=5015
container_tmp_port=5016
osrm_backend_port=5000

is_updated=false

mkdir ~/osrm-backend 2>null;

cd ~/osrm-backend

if ! [ -f $map_file ]; then
	wget $map_url
	touch $map_file
	update_map=true
fi

date_file=$(date -r $map_file +%s)
date_now=$(date +%s)

date_diff=$(($date_now - $date_file)) 
date_diff=$((date_diff / 2592000))
if (( $date_diff > 0 )); then
	wget $map_url
	touch $map_file
	update_map=true
fi

rm $lua_script_file
wget $custom_lua_script

if [ "$update_map" = true ]; then
	rm -rf $osrm_folder
	git clone $git_osrm
	cp $map_file $osrm_folder
fi

cp $lua_script_file $osrm_folder

cd $osrm_folder

docker container prune -f

if ! docker images "$image_name" | grep -q "$image_name" || [ "$update_map" = true ]; then
	docker run -t -v "${PWD}:/data/" "$image_name" osrm-extract -p "/data/$lua_script_file" "/data/$map_file" || echo "osrm-extract failed"
	docker run -t -v "${PWD}:/data/" "$image_name" osrm-partition "/data/brazil-latest.osrm" || echo "osrm-partition failed"
	docker run -t -v "${PWD}:/data/" "$image_name" osrm-customize "/data/brazil-latest.osrm" || echo "osrm-customize failed"
	is_updated=true
else
	echo "$image_name já é uma imagem e o mapa não foi atualizado"
fi

if [ "$( docker container inspect -f '{{.State.Status}}' $container_tmp_name 2>/dev/null )" == "running" ] > /dev/null; then
	docker stop "$container_tmp_name"
	docker rm "$container_tmp_name"
fi

if [ "$( docker container inspect -f '{{.State.Status}}' $container_prod_name 2>/dev/null )" == "running" ]; then
	docker run -t -d -p "$container_tmp_port":"$osrm_backend_port" -v "${PWD}:/data/" --name "$container_tmp_name" "$image_name" osrm-routed --algorithm mld /data/brazil-latest.osrm || echo "osrm-routed failed"
	url_tmp="http://127.0.0.1:$container_tmp_port/route/v1/driving/13.388860,52.517037;13.385983,52.496891"
	#echo curl --max-time 5 -s "$url"
	if wget --timeout=5 -q -O- "$url_tmp" >/dev/null; then
    		#echo "Connection to $url successful."
    		docker stop "$container_prod_name"
    		docker rename "$container_prod_name" old_"$container_prod_name"
    		docker run -t -d -p "$container_prod_port":"$osrm_backend_port" -v "${PWD}:/data/" --name "$container_prod_name" --restart=on-failure:10 "$image_name" osrm-routed --algorithm mld /data/brazil-latest.osrm || echo "osrm-routed failed"
    		docker rm old_"$container_prod_name"
		docker stop "$container_tmp_name"
		docker rm "$container_tmp_name"
		is_updated=true
	else
    		echo "Failed setup temporary container."
    		is_updated=false
	fi
else
#	echo "teste"
	docker run -t -d -p "$container_prod_port":"$osrm_backend_port" -v "${PWD}:/data/" --name "$container_prod_name" --restart=on-failure:10 "$image_name" osrm-routed --algorithm mld /data/brazil-latest.osrm || echo "osrm-routed failed"
fi


url="http://127.0.0.1:$container_prod_port/route/v1/driving/13.388860,52.517037;13.385983,52.496891"

if wget --timeout=5 -q -O- "$url" >/dev/null; then
	if [ "$is_update" = true ]; then
		echo "O servico OSRM está ATIVO e foi ATUALIZADO com sucesso. Pode ser rodado a partir da porta $container_prod_port"
	else
		echo "O servico OSRM NAO FOI ATUALIZADO, porém está ATIVO. Pode ser rodado a partir da porta $container_prod_port"
	fi
else
	echo "SERVICO INATIVO, olhar mensagem de erro"
fi	
