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
declare -A FAN_GROUPS
declare -A TEMP_MAPS

# ========================================
# UCI 配置加载
# ========================================
load_fan_group() {
	local section="$1"
	local enabled name fan_type sensor fan gpio gpio_active_high trigger_temp

	config_get_bool enabled "$section" enabled 0
	config_get name "$section" name "$section"
	config_get fan_type "$section" fan_type "pwm"
	config_get sensor "$section" sensor
	config_get fan "$section" fan
	config_get gpio "$section" gpio
	config_get gpio_active_high "$section" gpio_active_high "1"
	config_get trigger_temp "$section" trigger_temp "50"

	if [ "$enabled" -eq 1 ]; then
		FAN_GROUPS["${section}_enabled"]="$enabled"
		FAN_GROUPS["${section}_name"]="$name"
		FAN_GROUPS["${section}_type"]="$fan_type"
		FAN_GROUPS["${section}_sensor"]="$sensor"
		FAN_GROUPS["${section}_fan"]="$fan"
		FAN_GROUPS["${section}_gpio"]="$gpio"
		FAN_GROUPS["${section}_gpio_active_high"]="$gpio_active_high"
		FAN_GROUPS["${section}_trigger_temp"]="$trigger_temp"

		log_info "Loaded group: $name (type=$fan_type, sensor=$sensor)"
	fi
}

load_temp_map() {
	local section="$1"
	local group temperature speed

	config_get group "$section" group
	config_get temperature "$section" temperature
	config_get speed "$section" speed

	if [ -n "$group" ] && [ -n "$temperature" ] && [ -n "$speed" ]; then
		local current="${TEMP_MAPS[$group]}"
		if [ -z "$current" ]; then
			TEMP_MAPS["$group"]="$temperature:$speed"
		else
			TEMP_MAPS["$group"]="$current $temperature:$speed"
		fi
		log_debug "Loaded mapping for $group: $temperature°C -> PWM $speed"
	fi
}

load_config() {
	# 清空数组
	FAN_GROUPS=()
	TEMP_MAPS=()

	config_load fan_control
	config_foreach load_fan_group fan_group
	config_foreach load_temp_map map

	log_info "Configuration loaded, ${#FAN_GROUPS[@]} parameters, ${#TEMP_MAPS[@]} mappings"
}

# ========================================
# 硬件操作函数
# ========================================

# GPIO 操作
gpio_export() {
	local gpio_num="$1"
	local gpio_path="/sys/class/gpio/gpio${gpio_num}"

	if [ ! -d "$gpio_path" ]; then
		echo "$gpio_num" > /sys/class/gpio/export 2>/dev/null
		sleep 0.1
	fi

	if [ -d "$gpio_path" ]; then
		echo "out" > "${gpio_path}/direction" 2>/dev/null
		log_info "GPIO $gpio_num exported and set to output"
		return 0
	else
		log_error "Failed to export GPIO $gpio_num"
		return 1
	fi
}

gpio_set_value() {
	local gpio_num="$1"
	local value="$2"
	local gpio_path="/sys/class/gpio/gpio${gpio_num}/value"

	if [ -w "$gpio_path" ]; then
		echo "$value" > "$gpio_path" 2>/dev/null
		log_debug "GPIO $gpio_num set to $value"
		return 0
	else
		log_error "Cannot write to GPIO $gpio_num"
		return 1
	fi
}

gpio_unexport() {
	local gpio_num="$1"
	echo "$gpio_num" > /sys/class/gpio/unexport 2>/dev/null
}

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
	local temp_maps="$2"
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
control_pwm_fan() {
	local group_id="$1"
	local sensor="${FAN_GROUPS[${group_id}_sensor]}"
	local fan="${FAN_GROUPS[${group_id}_fan]}"
	local name="${FAN_GROUPS[${group_id}_name]}"
	local temp_maps="${TEMP_MAPS[$group_id]}"

	if [ -z "$sensor" ] || [ -z "$fan" ]; then
		log_warn "[$name] Sensor or fan path not configured"
		return 1
	fi

	# 查找温度输入文件
	local temp_input=$(find_temp_input "$sensor")
	if [ -z "$temp_input" ]; then
		return 1
	fi

	# 查找 PWM 输出文件
	local pwm_output=$(find_pwm_output "$fan")
	if [ -z "$pwm_output" ]; then
		return 1
	fi

	# 读取当前温度
	local current_temp_milli=$(read_temp "$temp_input")
	local current_temp_c=$((current_temp_milli / 1000))

	log_debug "[$name] Current temperature: ${current_temp_c}°C"

	# 计算目标 PWM
	local target_pwm=$(calculate_target_pwm "$current_temp_c" "$temp_maps")

	log_info "[$name] Temperature: ${current_temp_c}°C -> PWM: $target_pwm"

	# 设置风扇速度
	set_fan_speed "$pwm_output" "$target_pwm"
}

control_dc_fan() {
	local group_id="$1"
	local sensor="${FAN_GROUPS[${group_id}_sensor]}"
	local gpio="${FAN_GROUPS[${group_id}_gpio]}"
	local gpio_active_high="${FAN_GROUPS[${group_id}_gpio_active_high]}"
	local trigger_temp="${FAN_GROUPS[${group_id}_trigger_temp]}"
	local name="${FAN_GROUPS[${group_id}_name]}"

	if [ -z "$sensor" ] || [ -z "$gpio" ]; then
		log_warn "[$name] Sensor or GPIO not configured"
		return 1
	fi

	# 确保 GPIO 已导出
	gpio_export "$gpio"

	# 查找温度输入文件
	local temp_input=$(find_temp_input "$sensor")
	if [ -z "$temp_input" ]; then
		return 1
	fi

	# 读取当前温度
	local current_temp_milli=$(read_temp "$temp_input")
	local current_temp_c=$((current_temp_milli / 1000))

	log_debug "[$name] Current temperature: ${current_temp_c}°C, trigger: ${trigger_temp}°C"

	# 判断是否需要开启风扇
	local fan_state=0
	if [ "$current_temp_c" -ge "$trigger_temp" ]; then
		fan_state=1
	fi

	# 根据有效电平设置 GPIO
	local gpio_value=$fan_state
	if [ "$gpio_active_high" -eq 0 ]; then
		gpio_value=$((1 - fan_state))
	fi

	log_info "[$name] Temperature: ${current_temp_c}°C -> Fan: $([ $fan_state -eq 1 ] && echo 'ON' || echo 'OFF')"

	gpio_set_value "$gpio" "$gpio_value"
}

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

	# 获取所有启用的组ID
	local enabled_groups=""

	while true; do
		load_config

		# 找出所有启用的组
		enabled_groups=""
		for key in "${!FAN_GROUPS[@]}"; do
			if [[ "$key" =~ _enabled$ ]]; then
				local group_id="${key%_enabled}"
				if [ "${FAN_GROUPS[$key]}" -eq 1 ]; then
					enabled_groups="$enabled_groups $group_id"
				fi
			fi
		done

		if [ -z "$enabled_groups" ]; then
			log_debug "No fan groups enabled, sleeping"
			sleep 10
			continue
		fi

		# 控制每个启用的组
		for group_id in $enabled_groups; do
			local fan_type="${FAN_GROUPS[${group_id}_type]}"

			case "$fan_type" in
				pwm)
					control_pwm_fan "$group_id"
					;;
				dc)
					control_dc_fan "$group_id"
					;;
				*)
					log_warn "Unknown fan type: $fan_type for group $group_id"
					;;
			esac
		done

		sleep 5
	done
}

# 启动主循环
main_loop
