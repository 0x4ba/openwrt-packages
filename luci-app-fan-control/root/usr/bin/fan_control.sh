#!/bin/sh

. /lib/functions.sh

# ========================================
# 日志系统
# ========================================
LOG_TAG="fan_control"
LOG_LEVEL=3  # 0=none, 1=error, 2=warning, 3=info, 4=debug

log_error() { [ "$LOG_LEVEL" -ge 1 ] && logger -t "$LOG_TAG" -p daemon.err "$1"; }
log_warn()  { [ "$LOG_LEVEL" -ge 2 ] && logger -t "$LOG_TAG" -p daemon.warning "$1"; }
log_info()  { [ "$LOG_LEVEL" -ge 3 ] && logger -t "$LOG_TAG" -p daemon.info "$1"; }
log_debug() { [ "$LOG_LEVEL" -ge 4 ] && logger -t "$LOG_TAG" -p daemon.debug "$1"; }

# ========================================
# 全局变量
# ========================================
enabled=""
sensor=""
fan=""
temp_maps=""

# ========================================

# ========================================
# UCI 配置加载
# ========================================

get_temp_map() {
	local temperature speed
	config_get temperature "$1" temperature
	config_get speed "$1" speed

	if [ -n "$temperature" ] && [ -n "$speed" ]; then
		temp_maps="$temp_maps$temperature:$speed "
	fi
}

load_global_maps() {
	temp_maps=""
	config_load fan_control
	config_foreach get_temp_map map
	log_debug "Temperature mappings: $temp_maps"
}

# ========================================
# 硬件操作函数
# ========================================
find_temp_input() {
	local sensor_dir="$1"
	local file

	# log_debug "Searching temperature input in: $sensor_dir"

	if [ ! -d "$sensor_dir" ]; then
		log_error "Sensor directory does not exist: $sensor_dir"
		return 1
	fi

	for file in $sensor_dir/temp*_input; do
		[ -e "$file" ] || continue
		if [ -r "$file" ]; then
			echo "$file"
			return 0
		fi
	done

	return 1
}

find_pwm_output() {
	local fan_dir="$1"
	local file

	# log_debug "Searching PWM output in: $fan_dir"

	if [ ! -d "$fan_dir" ]; then
		log_error "Fan directory does not exist: $fan_dir"
		return 1
	fi

	for file in $fan_dir/pwm[0-9]*; do
		[ -e "$file" ] || continue
		
		case "$(basename "$file")" in
			*_enable) continue ;;
		esac

		if [ -w "$file" ]; then
			echo "$file"
			return 0
		fi
	done

	return 1
}

read_temp() {
	local temp_path="$1"
	if [ -r "$temp_path" ]; then
		cat "$temp_path" 2>/dev/null || echo 0
	else
		echo 0
	fi
}

set_fan_speed() {
	local pwm_path="$1"
	local speed="$2"

	if [ ! -w "$pwm_path" ]; then
		log_error "PWM path not writable: $pwm_path"
		return 1
	fi

	if echo "$speed" > "$pwm_path" 2>/dev/null; then
		# log_debug "Fan speed set: $speed -> $pwm_path"
		return 0
	else
		log_error "Failed to write speed $speed to $pwm_path"
		return 1
	fi
}

# ========================================
# 温度到 PWM 映射计算
# ========================================
calculate_target_pwm() {
	local current_temp="$1"
	local target_pwm=0
	local highest_matching_temp=-999

	for mapping in $temp_maps; do
		local temp="${mapping%%:*}"
		local speed="${mapping##*:}"

		# 温度 >= 阈值时使用对应速度
		if [ "$current_temp" -ge "$temp" ] && [ "$temp" -ge "$highest_matching_temp" ]; then
			highest_matching_temp="$temp"
			target_pwm="$speed"
		fi
	done

	echo "$target_pwm"
}

# ========================================
# 单个控制组处理
# ========================================
process_control_group() {
	local section="$1"
	local enabled sensor fans

	config_get_bool enabled "$section" enabled 0
	config_get sensor "$section" sensor
	
	# 支持 list fan (DynamicList) 和 option fan (MultiValue space-separated)
	fans=""
	append_fan() {
		fans="$fans $1"
	}
	config_list_foreach "$section" fan append_fan

	if [ "$enabled" -ne 1 ]; then
		return
	fi

	if [ -z "$sensor" ] || [ -z "$fans" ]; then
		return
	fi

	# 查找温度输入
	local temp_input
	temp_input=$(find_temp_input "$sensor")
	if [ -z "$temp_input" ]; then
		log_warn "[$section] Sensor input not found: $sensor"
		return
	fi

	# 读取温度
	local current_temp_milli current_temp_c
	current_temp_milli=$(read_temp "$temp_input")
	current_temp_c=$((current_temp_milli / 1000))

	# 计算目标 PWM
	local target_pwm
	target_pwm=$(calculate_target_pwm "$current_temp_c")

	log_info "[$section] Temp: ${current_temp_c}°C -> PWM: $target_pwm"

	# 应用到所有风扇
	for fan_path in $fans; do
		local pwm_output
		pwm_output=$(find_pwm_output "$fan_path")
		
		if [ -n "$pwm_output" ]; then
			set_fan_speed "$pwm_output" "$target_pwm"
		else
			log_warn "[$section] Fan output not found: $fan_path"
		fi
	done
}

# ========================================
# 主控制循环
# ========================================
main_loop() {
	log_info "Fan control service started"

	local retry=0
	while [ ! -d "/sys/class/hwmon" ] && [ $retry -lt 30 ]; do
		log_warn "Waiting for /sys/class/hwmon (attempt $((retry+1))/30)"
		sleep 1
		retry=$((retry+1))
	done

	if [ ! -d "/sys/class/hwmon" ]; then
		log_error "/sys/class/hwmon not available after 30s, exiting"
		return 1
	fi

	while true; do
		# 每次循环重新加载所有配置，以便实时生效（如果不嫌IO多的话，或者可以放在循环外，但OpenWrt通常服务不需重启改配置生效？）
		# 修正：通常服务需要reload/restart才能生效配置。这里为了简单，每次循环reload map。
		load_global_maps
		
		# 遍历所有 fan_control section
		config_foreach process_control_group fan_control

		sleep 5
	done
}

# 启动主循环
main_loop
