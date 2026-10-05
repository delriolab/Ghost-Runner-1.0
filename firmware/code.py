# ============================================================

# GHOSTRUNNER - PRODUCTION + BLE BATTERY SERVICE

# XIAO nRF52840 Sense + onboard LSM6DS3TR-C

#

# BEHAVIOR

# ------------------------------------------------------------

# FIRST USE:

#   5 deliberate taps -> activation stored in NVM

#

# NORMAL:

#   BLE advertising

#   833 Hz accelerometer

#   12 g hit detection

#   HIT sent over BLE UART

#

# IDLE:

#   30 seconds without meaningful motion

#   BLE stops

#   gyro off

#   accelerometer switches to 26 Hz / +/-2 g

#   IMU wake interrupt routed to INT1

#   MCU enters LIGHT SLEEP

#

# WAKE:

#   physical motion -> IMU_INT1 HIGH

#   light sleep returns

#   full 833 Hz sensing restored

#   BLE advertising restored

#

# NO DEEP SLEEP IS USED.

#

# GAME BREAK (only while the app asks for it):

#   app sends GAME   -> finger-tap detection, reply MODE:GAME

#   each tap sends HIT:<ms> stamped with the puck's own clock

#   app sends NORMAL -> back to 12 g hits, reply MODE:NORMAL

#   boot, disconnect and sleep always return to NORMAL

#   sleep waits 5 minutes instead of 30 seconds

# ============================================================





import time

import board

import digitalio

import analogio

import busio

import alarm

import microcontroller

import supervisor



from adafruit_ble import BLERadio

from adafruit_ble.advertising.standard import ProvideServicesAdvertisement

from adafruit_ble.services.nordic import UARTService

from adafruit_ble.services.standard import BatteryService



from adafruit_lsm6ds.lsm6ds3trc import LSM6DS3TRC

from adafruit_lsm6ds import AccelRange, Rate





# ============================================================

# GHOSTRUNNER SETTINGS

# ============================================================



DEVICE_NAME = "GhostRunner"



G_MS2 = 9.80665



# Existing working impact sensitivity

THRESH_G = 12.0



# Existing working cooldown

HIT_COOLDOWN_S = 2.80



# Awake loop delay

LOOP_SLEEP_S = 0.001





# ============================================================

# AUTO-SLEEP

# ============================================================



# Production setting:

# sleep after one minute without meaningful movement

SLEEP_AFTER_S = 30.0



# Movement needed to reset inactivity timer

ACTIVITY_CHANGE_G = 0.35





# ============================================================

# GAME BREAK MODE

# ============================================================



# Finger-tap detection, modeled on the first-use activation taps.

# Only used after the app sends GAME; normal hits are unchanged.

GAME_TAP_G = 3.0

GAME_REARM_G = 1.40

GAME_MIN_INTERVAL_S = 0.25



# Kids pause between turns, so Game mode waits longer before sleeping

GAME_SLEEP_AFTER_S = 300.0



# How often to check for app commands (keeps the hit loop fast)

COMMAND_POLL_S = 0.05





# ============================================================

# MOTION-WAKE

# ============================================================



# We physically verified 0x02 produces INT1 movement events

# on this XIAO Sense.

WAKE_THRESHOLD_REG = 0x02





# ============================================================

# FIRST ACTIVATION

# ============================================================



ACTIVATION_TAPS_REQUIRED = 5



ACTIVATION_TAP_G = 2.20

ACTIVATION_REARM_G = 1.40



ACTIVATION_MIN_INTERVAL_S = 0.18

ACTIVATION_TIMEOUT_S = 6.0



# Persistent activation signature: "GR"

ACTIVATION_MAGIC_0 = 0x47

ACTIVATION_MAGIC_1 = 0x52





# ============================================================

# LED

# ============================================================



AWAKE_LED_INTERVAL_S = 2.0

AWAKE_LED_ON_S = 0.040





# ============================================================

# LSM6DS3TR-C REGISTERS

# ============================================================



IMU_ADDR = 0x6A



CTRL1_XL = 0x10

CTRL2_G = 0x11



WAKE_UP_SRC = 0x1B



TAP_CFG = 0x58

WAKE_UP_THS = 0x5B

WAKE_UP_DUR = 0x5C



MD1_CFG = 0x5E





# ============================================================

# STATUS LED

# ============================================================



led = digitalio.DigitalInOut(board.LED)

led.direction = digitalio.Direction.OUTPUT





def led_on():

    # XIAO LED is active-low

    led.value = False





def led_off():

    led.value = True





def blink(count=1, on_time=0.08, off_time=0.08):



    for _ in range(count):



        led_on()

        time.sleep(on_time)



        led_off()

        time.sleep(off_time)





led_off()





# ============================================================

# IMU POWER

# ============================================================



imu_power = digitalio.DigitalInOut(board.IMU_PWR)



imu_power.direction = digitalio.Direction.OUTPUT



# IMPORTANT:

# The accelerometer must remain powered while sleeping

# because it generates the wake interrupt.

imu_power.value = True



time.sleep(0.50)





# ============================================================

# I2C

# ============================================================



imu_i2c = busio.I2C(

    scl=board.IMU_SCL,

    sda=board.IMU_SDA,

    frequency=400000

)





# ============================================================

# LSM6DS3TR-C

# ============================================================



imu = LSM6DS3TRC(imu_i2c)





# ============================================================

# RAW IMU REGISTER ACCESS

# ============================================================



def i2c_lock():



    while not imu_i2c.try_lock():

        pass





def write_reg(register, value):



    i2c_lock()



    try:



        imu_i2c.writeto(

            IMU_ADDR,

            bytes([register, value])

        )



    finally:



        imu_i2c.unlock()





def read_reg(register):



    data = bytearray(1)



    i2c_lock()



    try:



        imu_i2c.writeto_then_readfrom(

            IMU_ADDR,

            bytes([register]),

            data

        )



    finally:



        imu_i2c.unlock()



    return data[0]





# ============================================================

# ACCELERATION FUNCTIONS

# ============================================================



def get_acceleration_g():



    ax, ay, az = imu.acceleration



    return (

        ax / G_MS2,

        ay / G_MS2,

        az / G_MS2

    )





def magnitude_g(acceleration):



    x, y, z = acceleration



    return (

        x * x +

        y * y +

        z * z

    ) ** 0.5





def vector_change_g(a, b):



    dx = a[0] - b[0]

    dy = a[1] - b[1]

    dz = a[2] - b[2]



    return (

        dx * dx +

        dy * dy +

        dz * dz

    ) ** 0.5





# ============================================================

# ACTIVATION MEMORY

# ============================================================



def is_activated():



    return (

        microcontroller.nvm[0] == ACTIVATION_MAGIC_0

        and

        microcontroller.nvm[1] == ACTIVATION_MAGIC_1

    )





def save_activation():



    microcontroller.nvm[0] = ACTIVATION_MAGIC_0

    microcontroller.nvm[1] = ACTIVATION_MAGIC_1





# ============================================================

# NORMAL / AWAKE IMU MODE

# ============================================================



def configure_running_mode():



    # Disable wake interrupt routing while running normally.

    write_reg(

        MD1_CFG,

        0x00

    )



    # Full GhostRunner impact range

    imu.accelerometer_range = (

        AccelRange.RANGE_16G

    )



    # Full GhostRunner impact sampling rate

    imu.accelerometer_data_rate = (

        Rate.RATE_833_HZ

    )



    # Gyroscope unused

    imu.gyro_data_rate = (

        Rate.RATE_SHUTDOWN

    )



    # Clear old wake status

    try:

        read_reg(WAKE_UP_SRC)

    except Exception:

        pass



    time.sleep(0.05)





# ============================================================

# LOW-POWER MOTION-WAKE IMU MODE

# ============================================================



def configure_motion_wake():



    # --------------------------------------------------------

    # Accelerometer:

    #

    # ODR = 26 Hz

    # Full scale = +/-2 g

    #

    # CTRL1_XL = 0x20

    # --------------------------------------------------------



    write_reg(

        CTRL1_XL,

        0x20

    )



    # Gyroscope completely off

    write_reg(

        CTRL2_G,

        0x00

    )



    # --------------------------------------------------------

    # TAP_CFG = 0x90

    #

    # bit 7: INTERRUPTS_ENABLE

    # bit 4: SLOPE_FDS = high-pass wake filter

    # --------------------------------------------------------



    write_reg(

        TAP_CFG,

        0x90

    )



    # Wake threshold

    write_reg(

        WAKE_UP_THS,

        WAKE_THRESHOLD_REG

    )



    # No additional duration requirement

    write_reg(

        WAKE_UP_DUR,

        0x00

    )



    # Route wake-up event to INT1

    # MD1_CFG bit 5 = INT1_WU

    write_reg(

        MD1_CFG,

        0x20

    )



    # Clear any stale interrupt

    read_reg(

        WAKE_UP_SRC

    )



    time.sleep(0.10)





# ============================================================
# BATTERY MONITOR / DIAGNOSTIC
# ============================================================

BATTERY_DIVIDER_FACTOR = 3.02

battery_read_enable = digitalio.DigitalInOut(board.READ_BATT_ENABLE)
battery_read_enable.direction = digitalio.Direction.INPUT

battery_adc = analogio.AnalogIn(board.VBATT)


def battery_percent_from_voltage(voltage):

    curve = (
        (3.30, 0),
        (3.40, 3),
        (3.50, 7),
        (3.60, 15),
        (3.70, 30),
        (3.80, 50),
        (3.90, 65),
        (4.00, 80),
        (4.10, 90),
        (4.20, 100),
    )

    if voltage <= 3.30:
        return 0

    if voltage >= 4.20:
        return 100

    for i in range(1, len(curve)):

        low_v, low_pct = curve[i - 1]
        high_v, high_pct = curve[i]

        if voltage <= high_v:

            fraction = (
                (voltage - low_v)
                / (high_v - low_v)
            )

            return int(
                low_pct
                + fraction * (high_pct - low_pct)
                + 0.5
            )

    return 100


def read_battery():

    # XIAO nRF52840 Sense:
    # READ_BATT_ENABLE is active LOW.
    battery_read_enable.direction = (
        digitalio.Direction.OUTPUT
    )

    battery_read_enable.value = False

    time.sleep(0.003)

    # Throw-away samples allow ADC to settle.
    for _ in range(9):
        _ = battery_adc.value

    raw = battery_adc.value

    voltage = (
        raw / 65535.0
    ) * battery_adc.reference_voltage * BATTERY_DIVIDER_FACTOR

    # Return enable pin to high impedance.
    battery_read_enable.direction = (
        digitalio.Direction.INPUT
    )

    percent = battery_percent_from_voltage(
        voltage
    )

    return raw, voltage, percent


def print_battery_diagnostic():

    try:

        raw, voltage, percent = read_battery()

        # Also load the standard BLE Battery Level characteristic.
        battery_service.level = percent

        print("")
        print("==============================")
        print("BATTERY DIAGNOSTIC")
        print("==============================")
        print("Battery raw:", raw)
        print(
            "Battery voltage:",
            round(voltage, 2),
            "V"
        )
        print(
            "Battery level:",
            percent,
            "%"
        )
        print("==============================")
        print("")

    except Exception as error:

        try:
            battery_read_enable.direction = (
                digitalio.Direction.INPUT
            )
        except Exception:
            pass

        print("")
        print("==============================")
        print("BATTERY DIAGNOSTIC ERROR")
        print("==============================")
        print(error)
        print("==============================")
        print("")


# ============================================================

# BLE

# ============================================================



ble = BLERadio()



ble.name = DEVICE_NAME



uart = UARTService()

# Standard Bluetooth SIG Battery Service (0x180F).
# Battery Level characteristic is 0x2A19.
battery_service = BatteryService()



advertisement = ProvideServicesAdvertisement(

    uart

)





def ensure_advertising():



    if (

        not ble.connected

        and

        not ble.advertising

    ):



        try:



            ble.start_advertising(

                advertisement

            )



            print(

                "Advertising as:",

                DEVICE_NAME

            )



        except Exception as error:



            print(

                "Advertising error:",

                error

            )





def stop_ble():



    # Stop advertising

    if ble.advertising:



        try:

            ble.stop_advertising()



        except Exception:

            pass





    # Disconnect app if connected

    if ble.connected:



        try:



            for connection in ble.connections:



                try:

                    connection.disconnect()



                except Exception:

                    pass



        except Exception:

            pass



    time.sleep(0.10)





# ============================================================

# FIVE-TAP FIRST ACTIVATION

# ============================================================



def run_first_activation():



    print("")

    print("==============================")

    print("NEW GHOSTRUNNER")

    print("==============================")



    print(

        "Tap GhostRunner 5 times to activate"

    )



    configure_running_mode()



    # Give startup movement time to settle

    time.sleep(0.30)



    tap_count = 0



    armed = True



    sequence_start = None



    last_tap_time = (

        -ACTIVATION_MIN_INTERVAL_S

    )





    while True:



        now = time.monotonic()



        acceleration = (

            get_acceleration_g()

        )



        mag = magnitude_g(

            acceleration

        )





        # ----------------------------------------------------

        # RESET INCOMPLETE SEQUENCE

        # ----------------------------------------------------



        if (

            sequence_start is not None

            and

            now - sequence_start

            > ACTIVATION_TIMEOUT_S

        ):



            tap_count = 0



            sequence_start = None



            armed = True



            print(

                "Tap sequence reset"

            )





        # ----------------------------------------------------

        # TAP

        # ----------------------------------------------------



        if (

            armed

            and

            mag >= ACTIVATION_TAP_G

            and

            now - last_tap_time

            >= ACTIVATION_MIN_INTERVAL_S

        ):



            if tap_count == 0:



                sequence_start = now



            tap_count += 1



            last_tap_time = now



            armed = False





            print(

                "Tap:",

                tap_count,

                "/",

                ACTIVATION_TAPS_REQUIRED

            )





            blink(

                1,

                0.025,

                0.025

            )





            if (

                tap_count

                >= ACTIVATION_TAPS_REQUIRED

            ):



                save_activation()



                print("")

                print("==============================")

                print("GHOSTRUNNER ACTIVATED")

                print("==============================")



                blink(

                    5,

                    0.08,

                    0.08

                )



                return





        # ----------------------------------------------------

        # REARM

        # ----------------------------------------------------



        if (

            not armed

            and

            mag <= ACTIVATION_REARM_G

        ):



            armed = True





        time.sleep(

            0.005

        )





# ============================================================

# LIGHT SLEEP / MOTION WAKE

# ============================================================



def enter_motion_sleep():



    print("")

    print("==============================")

    print("GHOSTRUNNER SLEEPING")

    print("==============================")



    # BLE radio activity stopped

    stop_ble()



    # LED completely off

    led_off()



    # Put IMU into low-power motion mode

    configure_motion_wake()





    # --------------------------------------------------------

    # MAKE SURE INT1 IS LOW BEFORE ARMING

    # --------------------------------------------------------



    int1 = digitalio.DigitalInOut(

        board.IMU_INT1

    )



    int1.direction = (

        digitalio.Direction.INPUT

    )





    settle_start = (

        time.monotonic()

    )





    while (

        int1.value

        and

        time.monotonic() - settle_start

        < 3.0

    ):



        # Clear current wake condition

        try:

            read_reg(WAKE_UP_SRC)



        except Exception:

            pass



        time.sleep(

            0.05

        )





    print(

        "INT1 before sleep:",

        int1.value

    )



    int1.deinit()





    # --------------------------------------------------------

    # ARM MOTION ALARM

    # --------------------------------------------------------



    motion_alarm = alarm.pin.PinAlarm(

        pin=board.IMU_INT1,

        value=True,

        pull=False

    )





    print(

        "Motion wake armed"

    )



    print(

        "Waiting for movement..."

    )



    led_off()





    # ========================================================

    # IMPORTANT DIFFERENCE:

    #

    # LIGHT SLEEP, NOT DEEP SLEEP.

    #

    # This function RETURNS after IMU_INT1 wakes us.

    # ========================================================



    wake_source = (

        alarm.light_sleep_until_alarms(

            motion_alarm

        )

    )





    # ========================================================

    # WE ARE AWAKE AGAIN

    # ========================================================



    print("")

    print("==============================")

    print("MOTION DETECTED - AWAKE")

    print("==============================")





    # Clear wake event

    try:

        read_reg(WAKE_UP_SRC)



    except Exception:

        pass





    # Restore full-speed IMU

    configure_running_mode()





    # Very obvious visual wake confirmation

    blink(

        4,

        0.07,

        0.07

    )





    # Restart BLE

    ensure_advertising()





    print(

        "GhostRunner ready"

    )





# ============================================================

# STARTUP

# ============================================================



print("")

print("==============================")

print("GHOSTRUNNER")

print("==============================")



print(

    "Onboard IMU connected"

)





# ============================================================

# FIRST-EVER ACTIVATION

# ============================================================



if not is_activated():



    run_first_activation()





# ============================================================

# NORMAL RUNNING CONFIGURATION

# ============================================================



configure_running_mode()





print("")

print(

    "Impact threshold:",

    THRESH_G,

    "g"

)



print(

    "Hit cooldown:",

    HIT_COOLDOWN_S,

    "seconds"

)



print(

    "Sleep timeout:",

    SLEEP_AFTER_S,

    "seconds"

)



print(

    "Automatic motion wake: ON"

)



print(

    "Sleep type: LIGHT SLEEP"

)





# Three flashes = normal ready

blink(

    3,

    0.08,

    0.08

)





print("")

print(

    "GhostRunner ready"

)





# ============================================================

# BLE START

# ============================================================



ensure_advertising()





# ============================================================

# HEARTBEAT STATE

# ============================================================



awake_led_last_pulse = (

    time.monotonic()

)



awake_led_is_on = False



awake_led_on_time = 0.0





def update_awake_led(now):



    global awake_led_last_pulse

    global awake_led_is_on

    global awake_led_on_time





    # Start pulse

    if (

        not awake_led_is_on

        and

        now - awake_led_last_pulse

        >= AWAKE_LED_INTERVAL_S

    ):



        led_on()



        awake_led_is_on = True



        awake_led_on_time = now



        awake_led_last_pulse = now





    # End pulse

    if (

        awake_led_is_on

        and

        now - awake_led_on_time

        >= AWAKE_LED_ON_S

    ):



        led_off()



        awake_led_is_on = False





# ============================================================

# GAME BREAK COMMANDS

# ============================================================

#

# The app sends one command per line over BLE UART.

# GAME and NORMAL switch modes and are acknowledged.

# Anything else (the app's START / STOP / T= lines) is ignored,

# exactly as before. Game mode is never stored in NVM.



game_mode = False

game_tap_armed = True

last_game_tap_time = -GAME_MIN_INTERVAL_S

command_buffer = b""

last_command_check = time.monotonic()

sample_ms = 0





def send_line(text):

    try:

        uart.write((text + "\n").encode())

    except Exception as error:

        print("BLE send error:", error)





def set_game_mode(enabled):

    global game_mode, game_tap_armed, last_game_tap_time

    if enabled != game_mode:

        print("Mode:", "GAME" if enabled else "NORMAL")

    game_mode = enabled

    # Every Game session starts armed for a fresh first tap

    game_tap_armed = True

    last_game_tap_time = -GAME_MIN_INTERVAL_S





def handle_command(line):

    if line == b"GAME":

        set_game_mode(True)

        send_line("MODE:GAME")

    elif line == b"NORMAL":

        set_game_mode(False)

        send_line("MODE:NORMAL")





def poll_commands():

    # Reads only bytes that have already arrived, so it never waits

    global command_buffer

    try:

        waiting = uart.in_waiting

        if not waiting:

            return

        data = uart.read(waiting)

    except Exception as error:

        print("BLE read error:", error)

        return

    if not data:

        return

    command_buffer += data

    while b"\n" in command_buffer:

        line, command_buffer = command_buffer.split(b"\n", 1)

        handle_command(line.strip())

    # Drop runaway input that never ends a line

    if len(command_buffer) > 64:

        command_buffer = b""





# ============================================================

# RUNTIME STATE

# ============================================================



last_hit_time = (

    -HIT_COOLDOWN_S

)



last_activity_time = (

    time.monotonic()

)



previous_acceleration = (

    get_acceleration_g()

)



was_connected = False





# ============================================================

# MAIN LOOP

# ============================================================



while True:



    now = (

        time.monotonic()

    )





    # --------------------------------------------------------

    # BLE

    # --------------------------------------------------------



    ensure_advertising()



    connected = (

        ble.connected

    )




    if (

        connected

        and

        not was_connected

    ):



        print(

            "BLE connected"

        )



        blink(

            2

        )


        # Refresh standard BLE Battery Level when the app connects.
        try:
            raw, battery_voltage, battery_percent = read_battery()
            battery_service.level = battery_percent
        except Exception:
            pass






    if (

        not connected

        and

        was_connected

    ):



        print(

            "BLE disconnected"

        )



        # Never stay in Game mode without the app

        set_game_mode(False)

        command_buffer = b""





    was_connected = (

        connected

    )



    if (

        connected

        and

        now - last_command_check

        >= COMMAND_POLL_S

    ):

        last_command_check = now

        poll_commands()





    # --------------------------------------------------------

    # HEARTBEAT

    # --------------------------------------------------------



    update_awake_led(

        now

    )





    # --------------------------------------------------------

    # ACCELERATION

    # --------------------------------------------------------



    current_acceleration = (

        get_acceleration_g()

    )



    current_magnitude = (

        magnitude_g(

            current_acceleration

        )

    )



    # Game Break taps are timed from the moment this sample was read

    if game_mode:

        sample_ms = supervisor.ticks_ms()





    # --------------------------------------------------------

    # GENERAL ACTIVITY

    # --------------------------------------------------------



    movement_change = (

        vector_change_g(

            current_acceleration,

            previous_acceleration

        )

    )





    previous_acceleration = (

        current_acceleration

    )





    if (

        movement_change

        >= ACTIVITY_CHANGE_G

    ):



        last_activity_time = (

            now

        )





    # --------------------------------------------------------

    # HIT DETECTION

    # --------------------------------------------------------



    if not game_mode:



        delta_g = abs(

            current_magnitude - 1.0

        )





        cooldown_finished = (

            now - last_hit_time

            >= HIT_COOLDOWN_S

        )





        if (

            cooldown_finished

            and

            delta_g >= THRESH_G

        ):



            last_hit_time = (

                now

            )



            last_activity_time = (

                now

            )





            print(

                "HIT!",

                "magnitude:",

                current_magnitude,

                "delta:",

                delta_g

            )





            blink(

                2,

                0.04,

                0.04

            )





            if connected:



                try:



                    uart.write(

                        b"HIT\n"

                    )



                    print(

                        "Sent: HIT"

                    )





                except Exception as error:



                    print(

                        "BLE send error:",

                        error

                    )



    else:



        # GAME BREAK TAP DETECTION

        # Same trigger / settle / rearm idea as the activation taps.

        # The tap is stamped with the puck's own millisecond clock.

        if (

            game_tap_armed

            and

            current_magnitude >= GAME_TAP_G

            and

            now - last_game_tap_time

            >= GAME_MIN_INTERVAL_S

        ):

            game_tap_armed = False

            last_game_tap_time = now

            last_activity_time = now

            if connected:

                send_line("HIT:" + str(sample_ms))

            print("TAP!", "magnitude:", current_magnitude, "ms:", sample_ms)

            blink(1, 0.025, 0)



        if (

            not game_tap_armed

            and

            current_magnitude <= GAME_REARM_G

        ):

            game_tap_armed = True





    # --------------------------------------------------------

    # AUTO-SLEEP

    # --------------------------------------------------------



    inactivity = (

        now - last_activity_time

    )





    sleep_after_s = (

        GAME_SLEEP_AFTER_S if game_mode else SLEEP_AFTER_S

    )



    if (

        inactivity

        >= sleep_after_s

    ):



        print(

            "Inactivity:",

            inactivity,

            "seconds"

        )





        enter_motion_sleep()





        # ----------------------------------------------------

        # LIGHT SLEEP RETURNED:

        # reset awake runtime state

        # ----------------------------------------------------



        now = (

            time.monotonic()

        )





        last_activity_time = (

            now

        )





        previous_acceleration = (

            get_acceleration_g()

        )





        awake_led_last_pulse = (

            now

        )





        awake_led_is_on = False





        led_off()





        was_connected = False



        # Sleep dropped the app connection: wake up in NORMAL

        set_game_mode(False)

        command_buffer = b""





    # --------------------------------------------------------

    # LOOP DELAY

    # --------------------------------------------------------



    time.sleep(

        LOOP_SLEEP_S

    )
