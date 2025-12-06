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
# UCI 配置加载
# ========================================
get_main_config() {
	config_get_bool enabled "$1" enabled 0
	config_get sensor "$1" sensor
	config_get fan "$1" fan
}

get_temp_map() {
	local temperature speed
	config_get temperature "$1" temperature
	config_get speed "$1" speed

	if [ -n "$temperature" ] && [ -n "$speed" ]; then
		temp_maps="$temp_maps$temperature:$speed "
	fi
}

load_config() {
	enabled=""
	sensor=""
	fan=""
	temp_maps=""

	config_load fan_control
	config_foreach get_main_config fan_control
	config_foreach get_temp_map map

	log_info "Configuration loaded: enabled=$enabled, sensor=$sensor, fan=$fan"
	log_debug "Temperature mappings: $temp_maps"
}

# ========================================
# 硬件操作函数
# ========================================
find_temp_input() {
	local sensor_dir="$1"
	local file

	log_debug "Searching temperature input in: $sensor_dir"

	if [ ! -d "$sensor_dir" ]; then
		log_error "Sensor directory does not exist: $sensor_dir"
		return 1
	fi

	# 修复：移除引号以启用通配符展开
	for file in $sensor_dir/temp*_input; do
		[ -e "$file" ] || continue  # 跳过不存在的通配符字面值
		if [ -r "$file" ]; then
			log_info "Found temperature input: $file"
			echo "$file"
			return 0
		fi
	done

	log_warn "No readable temperature input in: $sensor_dir"
	return 1
}

find_pwm_output() {
	local fan_dir="$1"
	local file

	log_debug "Searching PWM output in: $fan_dir"

	if [ ! -d "$fan_dir" ]; then
		log_error "Fan directory does not exist: $fan_dir"
		return 1
	fi

	# 修复：移除引号以启用通配符展开
	for file in $fan_dir/pwm[0-9]*; do
		[ -e "$file" ] || continue

		# 排除 pwm*_enable 文件
		case "$(basename "$file")" in
			*_enable) continue ;;
		esac

		if [ -w "$file" ]; then
			log_info "Found PWM output: $file"
			echo "$file"
			return 0
		fi
	done

	log_warn "No writable PWM output in: $fan_dir"
	return 1
}

read_temp() {
	local temp_path="$1"
	if [ -r "$temp_path" ]; then
		cat "$temp_path" 2>/dev/null || echo 0
	else
		log_error "Cannot read temperature from: $temp_path"
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
		log_debug "Fan speed set: $speed -> $pwm_path"
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
# 主控制循环
# ========================================
main_loop() {
	log_info "Fan control service started"

	# 启动前等待 hwmon 子系统
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
		load_config

		if [ "$enabled" -ne 1 ]; then
			log_debug "Fan control disabled, sleeping"
			sleep 10
			continue
		fi

		if [ -z "$sensor" ] || [ -z "$fan" ]; then
			log_warn "Sensor or fan path not configured, sleeping"
			sleep 10
			continue
		fi

		# 查找温度输入文件
		temp_input=$(find_temp_input "$sensor")
		if [ -z "$temp_input" ]; then
			sleep 5
			continue
		fi

		# 查找 PWM 输出文件
		pwm_output=$(find_pwm_output "$fan")
		if [ -z "$pwm_output" ]; then
			sleep 5
			continue
		fi

		# 读取当前温度
		current_temp_milli=$(read_temp "$temp_input")
		current_temp_c=$((current_temp_milli / 1000))

		log_debug "Current temperature: ${current_temp_c}°C"

		# 计算目标 PWM
		target_pwm=$(calculate_target_pwm "$current_temp_c")

		log_info "Temperature: ${current_temp_c}°C -> PWM: $target_pwm"

		# 设置风扇速度
		set_fan_speed "$pwm_output" "$target_pwm"

		sleep 5
	done
}

# 启动主循环
main_loop
