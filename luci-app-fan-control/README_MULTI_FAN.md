# 多风扇控制功能说明

## 功能概述

此版本支持多组风扇控制，可以同时控制多个风扇，每个风扇组独立配置：
- 支持 **PWM 风扇**（多档调速）
- 支持 **直流风扇**（GPIO 开关控制）
- 每组可以选择不同的温度传感器
- 可自由组合温度源和风扇

## 主要特性

### 1. 多组控制
- 可创建多个风扇控制组
- 每组独立配置启用/禁用
- 每组有自己的名称标识
- 支持任意数量的风扇组

### 2. 风扇类型

#### PWM 风扇（多档调速）
- **控制方式**: 通过 hwmon PWM 接口
- **速度控制**: 0-255 PWM 值
- **温度映射**: 支持多个温度档位
- **适用场景**: 需要精细调速的4线/3线PWM风扇

**配置示例**:
```
config fan_group 'group1'
	option enabled '1'
	option name 'CPU风扇'
	option fan_type 'pwm'
	option sensor '/sys/class/hwmon/hwmon0'
	option fan '/sys/class/hwmon/hwmon1'

config map
	option group 'group1'
	option temperature '40'
	option speed '100'

config map
	option group 'group1'
	option temperature '60'
	option speed '200'
```

#### 直流风扇（GPIO 开关）
- **控制方式**: 通过 GPIO + MOS 管
- **速度控制**: 仅开/关两种状态
- **温度触发**: 单一温度阈值
- **适用场景**: 简单的2线直流风扇

**配置示例**:
```
config fan_group 'group2'
	option enabled '1'
	option name '机箱风扇'
	option fan_type 'dc'
	option sensor '/sys/class/hwmon/hwmon0'
	option gpio '17'
	option gpio_active_high '1'
	option trigger_temp '50'
```

### 3. GPIO 有效电平

- **High (1=On)**: GPIO 输出高电平时风扇开启
- **Low (0=On)**: GPIO 输出低电平时风扇开启（反向逻辑）

根据你的 MOS 管电路选择正确的有效电平。

## 配置文件结构

### 风扇组配置 (fan_group)

| 选项 | 类型 | 说明 | PWM | DC |
|------|------|------|-----|-----|
| enabled | 0/1 | 启用此组 | ✓ | ✓ |
| name | 文本 | 组名称 | ✓ | ✓ |
| fan_type | pwm/dc | 风扇类型 | ✓ | ✓ |
| sensor | 路径 | 温度传感器路径 | ✓ | ✓ |
| fan | 路径 | PWM 风扇路径 | ✓ | - |
| gpio | 数字 | GPIO 引脚号 | - | ✓ |
| gpio_active_high | 0/1 | GPIO 有效电平 | - | ✓ |
| trigger_temp | 数字 | 触发温度(°C) | - | ✓ |

### 温度映射表 (map)

仅用于 PWM 风扇组：

| 选项 | 说明 |
|------|------|
| group | 所属风扇组ID |
| temperature | 温度阈值(°C) |
| speed | PWM 值(0-255) |

## 使用示例

### 场景1: CPU PWM风扇 + 机箱直流风扇

```
# CPU PWM 风扇 - 根据 CPU 温度多档调速
config fan_group 'cpu_fan'
	option enabled '1'
	option name 'CPU Fan'
	option fan_type 'pwm'
	option sensor '/sys/class/hwmon/hwmon0'
	option fan '/sys/class/hwmon/hwmon1'

config map
	option group 'cpu_fan'
	option temperature '40'
	option speed '80'

config map
	option group 'cpu_fan'
	option temperature '50'
	option speed '120'

config map
	option group 'cpu_fan'
	option temperature '60'
	option speed '180'

config map
	option group 'cpu_fan'
	option temperature '70'
	option speed '255'

# 机箱直流风扇 - 温度达到 55°C 时开启
config fan_group 'case_fan'
	option enabled '1'
	option name 'Case Fan'
	option fan_type 'dc'
	option sensor '/sys/class/hwmon/hwmon0'
	option gpio '17'
	option gpio_active_high '1'
	option trigger_temp '55'
```

### 场景2: 多个 PWM 风扇监控不同温度源

```
# 前置风扇 - 监控 CPU 温度
config fan_group 'front_fan'
	option enabled '1'
	option name 'Front Intake'
	option fan_type 'pwm'
	option sensor '/sys/class/hwmon/hwmon0'
	option fan '/sys/class/hwmon/hwmon1'

# 后置风扇 - 监控硬盘温度
config fan_group 'rear_fan'
	option enabled '1'
	option name 'Rear Exhaust'
	option fan_type 'pwm'
	option sensor '/sys/class/hwmon/hwmon2'
	option fan '/sys/class/hwmon/hwmon3'
```

## GPIO 使用说明

### 查找可用 GPIO

查看系统中可用的 GPIO：
```bash
ls /sys/class/gpio/
cat /sys/class/gpio/gpiochip*/base
cat /sys/class/gpio/gpiochip*/ngpio
```

### GPIO 编号

不同平台的 GPIO 编号不同，例如：
- **Raspberry Pi**: GPIO17 就是编号 17
- **某些 SoC**: 可能需要计算（base + offset）

### 测试 GPIO

手动测试 GPIO 控制：
```bash
# 导出 GPIO
echo 17 > /sys/class/gpio/export

# 设置为输出
echo out > /sys/class/gpio/gpio17/direction

# 开启风扇
echo 1 > /sys/class/gpio/gpio17/value

# 关闭风扇
echo 0 > /sys/class/gpio/gpio17/value

# 取消导出
echo 17 > /sys/class/gpio/unexport
```

## 日志查看

查看风扇控制日志：
```bash
logread | grep fan_control
```

实时监控：
```bash
logread -f | grep fan_control
```

## 故障排查

### PWM 风扇不工作
1. 检查 hwmon 设备是否存在: `ls /sys/class/hwmon/`
2. 检查 PWM 文件是否可写: `ls -l /sys/class/hwmon/hwmon*/pwm*`
3. 查看日志中的错误信息

### 直流风扇不工作
1. 检查 GPIO 是否正确导出: `ls /sys/class/gpio/gpio17`
2. 检查 GPIO 方向: `cat /sys/class/gpio/gpio17/direction`
3. 手动测试 GPIO（见上文）
4. 确认有效电平设置正确

### 温度读取失败
1. 检查温度传感器路径: `cat /sys/class/hwmon/hwmon0/temp*_input`
2. 确认传感器驱动已加载: `lsmod | grep hwmon`

## 注意事项

1. **GPIO 权限**: 确保脚本有权限操作 GPIO
2. **MOS 管电路**: 直流风扇需要 MOS 管驱动电路
3. **风扇电源**: GPIO 只能提供控制信号，风扇需要独立供电
4. **配置重载**: 修改配置后需重启服务: `/etc/init.d/fan_control restart`
5. **系统资源**: 每 5 秒检查一次温度，多组控制不会显著增加系统负担

## 升级说明

从旧版本升级时，需要手动迁移配置：

**旧配置**:
```
config fan_control 'fan_control'
	option enabled '1'
	option sensor '/sys/class/hwmon/hwmon0'
	option fan '/sys/class/hwmon/hwmon1'
```

**新配置**:
```
config fan_group 'group1'
	option enabled '1'
	option name 'Fan 1'
	option fan_type 'pwm'
	option sensor '/sys/class/hwmon/hwmon0'
	option fan '/sys/class/hwmon/hwmon1'
```

温度映射表需要添加 `group` 字段：
```
config map
	option group 'group1'  # 新增
	option temperature '50'
	option speed '150'
```
