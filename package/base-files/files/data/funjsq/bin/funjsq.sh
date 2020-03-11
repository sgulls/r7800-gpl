#! /bin/sh

#global vars
PLUGIN_PATH="data"

# $1: x.x.x $2: x.x.x (return true if $1 >= $2)
# v1 cu  v2 new
# 0--> have new version
check_new_version(){
	for n in 1 2 3
	do
		checkv1=$(echo $1 |awk -F. '{print $'$n'}')
		checkv2=$(echo $2 |awk -F. '{print $'$n'}')
		[ -z "$checkv2" ] && return 1 
		[ -z "$checkv1" ] && return 1

		if [ "$n" == "1" ]; then
			[ "$checkv2" -gt "$checkv1" ] && return 0
			[ "$checkv2" -lt "$checkv1" ] && return 1
		fi

		if [ "$n" == "2" ]; then
			[ "$checkv2" -gt "$checkv1" ] && return 0
			[ "$checkv2" -lt "$checkv1" ] && return 1
		fi

		if [ "$n" == "3" ]; then

			if [ "$checkv2" -gt "$checkv1" ]; then
				return 0
			else
				return 1
			fi
		fi
	done 

	return 1
}

sleep_time()
{
	case "$1" in
		1) echo 30 ;;
		2) echo 60 ;;
		3) echo 90 ;;
		4) echo 300 ;;
		5) echo 900 ;;
		6) echo 3600 ;;
		*) echo 86400 ;;
	esac
}

UPDATE_API_URL="https://update.funjsq.com/api/v1/plugin/"
BINARY_DL_URL="https://static.funjsq.com/web_control/wxapp/"
CONFIG_DL_URL="https://static.funjsq.com/web_control/plugin_config/wxapp/"
update_app_config()
{
	local update_type="data"
	local s_config_url="${UPDATE_API_URL}config_update?type=${update_type}"

	num=0
	while [ 1 ]; do
		local update_ret=$(curl -s -k -m 15 -H "Accept:text/plain" "${s_config_url}") 

		if [ "$?" == "0" ]; then

			update_md5=`echo $update_ret | cut -d ':' -f 1`	
			update_flag=`echo $update_ret | cut -d ':' -f 2`	
			md5_lenth=`echo -n $update_md5 | wc -c `
			
			[ "x$update_flag" = "x0" ] && return # don't update

			if [ "$md5_lenth" = "32" ]; then
				#update new config file
				tmp_config_path="/tmp/funjsq_plugin_config.tar.gz"
				if [ "x$update_flag" == "x1" ]; then

					old_md5="/tmp/.funjsq_old_config_md5"
					if [ -s $old_md5 ]; then
						local_md5=`cat $old_md5`	
						[ "x$update_md5" == "x$local_md5" ] && return
					fi
					
					d_config_url="${CONFIG_DL_URL}${update_type}/funjsq_config.tar.gz"
					curl  -s -k "$d_config_url" -o "${tmp_config_path}" >/dev/null 2>&1 

					if [ "$?" != "0" ]; then
						#download failed , clean up  file, and retry this flow
						[ -f "${tmp_config_path}" ] && rm  "${tmp_config_path}"
					else

						new_file_md5=`md5sum $tmp_config_path | cut -d ' ' -f 1` 

						if [ "x$new_file_md5" == "x$update_md5" ]; then
							tar -zxvf $tmp_config_path -C / > /dev/null
							echo -n $new_file_md5  > $old_md5
							rm -rf $tmp_config_path
							return
						fi						

						rm -rf $tmp_config_path
					fi

				fi
			fi
		fi

		[ "$num" = "10" ] && break
		num=$(($num + 1)) && sleep $(sleep_time $num)
	done

}


# update plugin version
start_update_app(){

	update_app_config &

	router_system="netgear"
	router_name="r7800"
	vs_path="/${PLUGIN_PATH}/funjsq/config/values/funjsq_version"
	local cu_version=`cat $vs_path`
	local update_version="2.0.0"
	[  -z $cu_version ] && cu_version="2.0.0"
	
	local s_version_url="${UPDATE_API_URL}version_update?system=${router_system}&type=${router_name}"

	num=0
	while [ 1 ]; do
		local update_data=$(curl -s -k -m 15 -H "Accept:text/plain" "${s_version_url}") 

		if [ "$?" == "0" ]; then

			update_version=`echo $update_data | cut -d '#' -f 1` 
			update_md5=`echo $update_data | cut -d '#' -f 2` 
			update_flag=`echo $update_data | cut -d '#' -f 3` 
			md5_lenth=`echo -n $update_md5 | wc -c `
			
			[ "x$update_flag" = "x0" ] && return # don't update


			if [ "$md5_lenth" = "32" ]; then

				check_new_version $cu_version $update_version  

				if [ "$?" == "0" ]; then
					tmp_binary_path="/tmp/funjsq_plugin.tar.gz"

					d_version_url="${BINARY_DL_URL}${router_system}/funjsq_plugin_netgear_${router_name}.tar.gz"
					curl  -s -k "$d_version_url" -o "${tmp_binary_path}" >/dev/null 2>&1 

					if [ "$?" != "0" ]; then
						#download failed , clean up  file, and retry this flow
						[ -f "${tmp_binary_path}" ] && rm  "${tmp_binary_path}"
					else

						new_file_md5=`md5sum $tmp_binary_path | cut -d ' ' -f 1` 

						if [ "x$new_file_md5" == "x$update_md5" ]; then
							tar -zxvf $tmp_binary_path -C / > /dev/null

							/${PLUGIN_PATH}/funjsq/bin/funjsq_ctl update 
							echo "$update_version" >  /${PLUGIN_PATH}/funjsq/config/values/funjsq_version
							echo "$update_version" >  /${PLUGIN_PATH}/funjsq/config/values/funjsq_update_version
							nvram set funjsq_version="$update_version"
							nvram set funjsq_update_version="$update_version"
							rm  "${tmp_binary_path}"
							return
						fi						

						rm  "${tmp_binary_path}"
					fi
				else
					return
				fi
			fi
		fi

		[ "$num" = "10" ] && break
		num=$(($num + 1)) && sleep $(sleep_time $num)
	done
	
}

start_funjsq(){
#	stop_funjsq

	[ "x$1" == "x" ] && return
	[ "x$2" == "x" ] && return
	[ "x$3" == "x" ] && return

	load_modules > /dev/null  &

	NTP_time=`date -u | awk -F 'UTC' '{print $2}' | sed 's/ //g'`
	[ $NTP_time -lt 2018 ] && {
		#月日时分年，设定时间必须大于安装包生成时的时间
		date -s 111512122019
	}

	accMAC="$1"
	accType="$2"
	accArea="$3"
	board_name=`cat /module_name`

	[ "$board_name" == "XR500" ] && {
		json1=`ubus call com.netdumasoftware.autoadmin reserve '{ "field" : "pmark", "subfield" : "funjsq1", "bits" : 1 }'`
		mark1=`echo $json1 | awk -F 'mask' '{print $2}'  | cut -d ',' -f 1 | cut -d ':' -f 2| tr '\n' ' ' | sed  's/ //g' `
		[ "x$mark1" != "x" ] &&  {
			echo $mark1 > /data/funjsq/config/values/mark1
		}

		json2=`ubus call com.netdumasoftware.autoadmin reserve '{ "field" : "pmark", "subfield" : "funjsq2", "bits" : 1 }'`
		mark2=`echo $json2 | awk -F 'mask' '{print $2}'  | cut -d ',' -f 1 | cut -d ':' -f 2| tr '\n' ' ' | sed  's/ //g' `
		[ "x$mark2" != "x" ] &&  {
			echo $mark2 > /data/funjsq/config/values/mark2
		}

		json3=`ubus call com.netdumasoftware.autoadmin reserve '{ "field" : "pmark", "subfield" : "funjsq3", "bits" : 1 }'`
		mark3=`echo $json3 | awk -F 'mask' '{print $2}'  | cut -d ',' -f 1 | cut -d ':' -f 2| tr '\n' ' ' | sed  's/ //g' `
		[ "x$mark3" != "x" ] &&  {
			echo $mark3 > /data/funjsq/config/values/mark3
		}

		json4=`ubus call com.netdumasoftware.autoadmin reserve '{ "field" : "pmark", "subfield" : "funjsq4", "bits" : 1 }'`
		mark4=`echo $json4 | awk -F 'mask' '{print $2}'  | cut -d ',' -f 1 | cut -d ':' -f 2| tr '\n' ' ' | sed  's/ //g' `
		[ "x$mark4" != "x" ] &&  {
			echo $mark4 > /data/funjsq/config/values/mark4
		}

		json5=`ubus call com.netdumasoftware.autoadmin reserve '{ "field" : "pmark", "subfield" : "funjsq5", "bits" : 1 }'`
		mark5=`echo $json5 | awk -F 'mask' '{print $2}'  | cut -d ',' -f 1 | cut -d ':' -f 2| tr '\n' ' ' | sed  's/ //g' `
		[ "x$mark5" != "x" ] &&  {
			echo $mark5 > /data/funjsq/config/values/mark5
		}

		json100=`ubus call com.netdumasoftware.autoadmin reserve '{ "field" : "pmark", "subfield" : "funjsq100", "bits" : 1 }'`
		mark100=`echo $json100 | awk -F 'mask' '{print $2}'  | cut -d ',' -f 1 | cut -d ':' -f 2| tr '\n' ' ' | sed  's/ //g' `
		[ "x$mark100" != "x" ] &&  {
			echo $mark100 > /data/funjsq/config/values/mark100
		}

		json101=`ubus call com.netdumasoftware.autoadmin reserve '{ "field" : "pmark", "subfield" : "funjsq101", "bits" : 1 }'`
		mark101=`echo $json101 | awk -F 'mask' '{print $2}'  | cut -d ',' -f 1 | cut -d ':' -f 2| tr '\n' ' ' | sed  's/ //g' `
		[ "x$mark101" != "x" ] &&  {
			echo $mark101 > /data/funjsq/config/values/mark101

		}

		lable1=`ubus call com.netdumasoftware.autoadmin acquire_rtable '{ "label" : "funjsq_rtable1" }'`
		table_id1=`echo $lable1 | awk -F 'result' '{print $2}'  | cut -d ',' -f 1 | cut -d ':' -f 2| tr '\n' ' ' | sed  's/ //g' | sed  's/}//g'`
		[ "x$table_id1" != "x" ] &&  {
			echo $table_id1 > /data/funjsq/config/values/rtable_id1
		}

		lable2=`ubus call com.netdumasoftware.autoadmin acquire_rtable '{ "label" : "funjsq_rtable2" }'`
		table_id2=`echo $lable2 | awk -F 'result' '{print $2}'  | cut -d ',' -f 1 | cut -d ':' -f 2| tr '\n' ' ' | sed  's/ //g' | sed  's/}//g'`
		[ "x$table_id2" != "x" ] &&  {
			echo $table_id2 > /data/funjsq/config/values/rtable_id2
		}

		lable3=`ubus call com.netdumasoftware.autoadmin acquire_rtable '{ "label" : "funjsq_rtable3" }'`
		table_id3=`echo $lable3 | awk -F 'result' '{print $2}'  | cut -d ',' -f 1 | cut -d ':' -f 2| tr '\n' ' ' | sed  's/ //g' | sed  's/}//g'`
		[ "x$table_id3" != "x" ] &&  {
			echo $table_id3 > /data/funjsq/config/values/rtable_id3
		}

		lable4=`ubus call com.netdumasoftware.autoadmin acquire_rtable '{ "label" : "funjsq_rtable4" }'`
		table_id4=`echo $lable4 | awk -F 'result' '{print $2}'  | cut -d ',' -f 1 | cut -d ':' -f 2| tr '\n' ' ' | sed  's/ //g' | sed  's/}//g'`
		[ "x$table_id4" != "x" ] &&  {
			echo $table_id4 > /data/funjsq/config/values/rtable_id4
		}


		lable5=`ubus call com.netdumasoftware.autoadmin acquire_rtable '{ "label" : "funjsq_rtable5" }'`
		table_id5=`echo $lable5 | awk -F 'result' '{print $2}'  | cut -d ',' -f 1 | cut -d ':' -f 2| tr '\n' ' ' | sed  's/ //g' | sed  's/}//g'`
		[ "x$table_id5" != "x" ] &&  {
			echo $table_id5 > /data/funjsq/config/values/rtable_id5
		}


	}

	start_update_app &
	/data/funjsq/bin/funjsq_ctl start $accMAC  $accType $accArea >/dev/null 2>&1 &
	
}

stop_funjsq(){

	accMAC="$1"
	/data/funjsq/bin/funjsq_ctl stop $accMAC >/dev/null 2>&1
	nvram  commit &
}

GetStatus_funjsq(){

	/data/funjsq/bin/funjsq_ctl GetStatus > /www/mul_device.aspx 
	cat /www/mul_device.aspx
}

install_funjsq(){
	
	killall funjsq_ctl >/dev/null 2>&1
	killall funjsq_cli >/dev/null 2>&1
	killall funjsq_time.sh >/dev/null 2>&1
	
	/data/funjsq/bin/funjsq_ctl unbind >/dev/null 2>&1
	/data/funjsq/bin/funjsq_ctl install >/dev/null &
	nvram  commit &

}

uninstall_funjsq(){
	unbind_funjsq 
	/data/funjsq/bin/funjsq_ctl logout >/dev/null 2>&1
	nvram  commit &
}

unbind_funjsq(){
	start_update_app init &

	stop_funjsq
	/data/funjsq/bin/funjsq_ctl unbind >/dev/null 2>&1
	killall funjsq_ctl >/dev/null 2>&1
	nvram  commit &
}

LogOut_funjsq(){
	uninstall_funjsq
	nvram  commit &
}

init_funjsq(){
	funjsq_login=`nvram get funjsq_no_need_login`

	mkdir -p /data/funjsq/config/values

	start_update_app init &
	mkdir -p /data/funjsq/config/redis

	killall funjsq_redis funjsq_inetd funjsq_httpd 
	/data/funjsq/bin/funjsq_redis -d /data/funjsq/config/redis
	/data/funjsq/bin/funjsq_inetd


	[ "x$funjsq_login" != "x1" ]  && {
		killall funjsq_detect
		rm -rf /data/funjsq/config/values/*
		/data/funjsq/bin/funjsq_detect -i br0 -d
	}
	
	/data/funjsq/bin/funjsq_ctl init &
	nvram  commit &
}


insmod_module()
{
	module_name=$1

	if [ "$2"  == "1" ]; then
		insmod_flag=`cat /proc/modules |grep  "$module_name\ " | wc -l`
	else
		insmod_flag=`cat /proc/modules |grep  "$module_name" | wc -l`
	fi

	[ "$insmod_flag" == "0" ] && {
		mod_path=`find /lib/modules/ -name ${module_name}.ko`
                [ "x$mod_path" != "x" ] && insmod $mod_path
	}   
}

load_modules()
{
	insmod_module "tun" "1"
	insmod_module "ip_set" "1"
	insmod_module "ip_set_hash_net" "0"
	insmod_module "ip_set_hash_ip" "0"
	insmod_module "xt_set" "0"
}


#===========================================mini app========================================================
#获取加速器信息
get_plugin_info(){
	/data/funjsq/bin/funjsq_ctl plugin_info
}

#获取路由器信息信息
get_router_info(){

	start_update_app init &
	/data/funjsq/bin/funjsq_ctl router_info

}

wechat_login()
{
	start_update_app init &

	[ "x$1" == "x" ] && return

	nvram set funjsq_wx_token="$1"
	/data/funjsq/bin/funjsq_config set funjsq_access_token="$1"
	nvram set funjsq_no_need_login=1

	mkdir -p /data/funjsq/config/redis

	killall funjsq_redis funjsq_inetd funjsq_httpd 
	/data/funjsq/bin/funjsq_redis -d /data/funjsq/config/redis
	/data/funjsq/bin/funjsq_inetd
	
	/data/funjsq/bin/funjsq_ctl init & 
	nvram  commit &
	echo "success"

}
#===========================================end============================================================


ACTION=$1
case $ACTION in
init)
	init_funjsq
	;;
start)
	start_funjsq $2 $3 $4 &
	;;
restart)
	start_funjsq 
	;;
stop)
	stop_funjsq $2 
	;;
GetStatus)
	GetStatus_funjsq  
	;;
install)
	install_funjsq  
	;;
uninstall)
	stop_funjsq 
	uninstall_funjsq 
	;;
unbind)
	unbind_funjsq 
	;;
reset)
	unbind_funjsq 
	;;
get_plugin_info)
	get_plugin_info
	;;
get_router_info)
	get_router_info
	;;
login)
	wechat_login $2
	;;
update)
	start_update_app &
	;;

esac

