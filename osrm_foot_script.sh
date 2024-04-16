#!/bin/bash
	
map_url="https://download.geofabrik.de/south-america/brazil-latest.osm.pbf"
map_file="brazil-latest.osm.pbf"
git_osrm="https://github.com/Project-OSRM/osrm-backend.git"
osrm_folder="osrm-backend"
image_name="ghcr.io/project-osrm/osrm-backend"


lua_script_file="foot.lua"
map_extract_folder="foot_map"
image_tag="foot"
container_prod_port=5017
custom_lua_script="https://raw.githubusercontent.com/marcelobveras/osrm_custom_script/main/${lua_script_file}"

container_prod_name="osrm-backend-${image_tag}-prod"
container_tmp_name="osrm-backend-tmp"
container_tmp_port=5016
osrm_backend_port=5000
update_map=false
is_updated=false

mkdir "${HOME}/${osrm_folder}" 2>/dev/null;

cd "${HOME}/${osrm_folder}" || exit

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

rm -rf "${map_extract_folder}/"
git clone $git_osrm || true
mv "${osrm_folder}/" "${map_extract_folder}/"

cp $map_file $map_extract_folder
cp $lua_script_file $map_extract_folder
#
# cd ${map_extract_folder}
volume_path=${PWD}/${map_extract_folder}
#
docker container prune -f
#
image_name_final="${image_name}:${image_tag}"

if ! docker images "$image_name_final" | grep -q "$image_name_final" || [ "$update_map" = true ]; then
  docker run -t -v "${volume_path}:/data/" "$image_name" osrm-extract -p "/data/$lua_script_file" "/data/$map_file" || echo "osrm-extract failed"
 	docker image tag "$image_name" "$image_name_final"
 	docker run -t -v "${volume_path}:/data/" "$image_name_final" osrm-partition "/data/brazil-latest.osrm" || echo "osrm-partition failed"
 	docker run -t -v "${volume_path}:/data/" "$image_name_final" osrm-customize "/data/brazil-latest.osrm" || echo "osrm-customize failed"
 	is_updated=true
else
  echo "$image_name_final já é uma imagem e o mapa não foi atualizado"
fi

if [ "$( docker container inspect -f '{{.State.Status}}' $container_tmp_name 2>/dev/null )" == "running" ] > /dev/null; then
  docker stop "$container_tmp_name"
  docker rm "$container_tmp_name"
fi

if [ "$( docker container inspect -f '{{.State.Status}}' $container_prod_name 2>/dev/null )" == "running" ]; then
  docker run -t -d -p "$container_tmp_port":"$osrm_backend_port" -v "${volume_path}:/data/" --name "$container_tmp_name" "$image_name_final" osrm-routed --algorithm mld /data/brazil-latest.osrm || echo "osrm-routed failed"
  url_tmp="http://127.0.0.1:$container_tmp_port/route/v1/driving/13.388860,52.517037;13.385983,52.496891"
  #echo curl --max-time 5 -s "$url"
  if wget --timeout=5 -q -O- "$url_tmp" >/dev/null; then
    #echo "Connection to $url successful."
    docker stop "$container_prod_name"
    docker rename "$container_prod_name" old_"$container_prod_name"
    docker run -t -d -p "$container_prod_port":"$osrm_backend_port" -v "${volume_path}:/data/" --name "$container_prod_name" --restart=on-failure:10 "$image_name_final" osrm-routed --algorithm mld /data/brazil-latest.osrm || echo "osrm-routed failed"
    docker rm old_"$container_prod_name"
    docker stop "$container_tmp_name"
    docker rm "$container_tmp_name"
    is_updated=true
  else
    echo "Failed setup temporary container."
    is_updated=false
  fi
else
	echo run -t -d -p "$container_prod_port":"$osrm_backend_port" -v "${volume_path}:/data/" --name "$container_prod_name" --restart=on-failure:10 "$image_name_final" osrm-routed --algorithm mld /data/brazil-latest.osrm
  docker run -t -d -p "$container_prod_port":"$osrm_backend_port" -v "${volume_path}:/data/" --name "$container_prod_name" --restart=on-failure:10 "$image_name_final" osrm-routed --algorithm mld /data/brazil-latest.osrm || echo "osrm-routed failed"
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
