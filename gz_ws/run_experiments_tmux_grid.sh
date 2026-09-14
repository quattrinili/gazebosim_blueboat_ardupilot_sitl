#!/bin/bash

# Configuration
BASE_WS="/home/blueboat_sitl/gz_ws"
CURRENTS=(0.0 0.2 0.4)
STRATEGIES=("active" "passive")
REPETITIONS=3  # Total number of complete batches
TIMEOUT=900

TEMPLATE_PATH="${BASE_WS}/src/asv_wave_sim/gz-waves-models/worlds/waves.sdf.template"
TARGET_SDF="${BASE_WS}/src/asv_wave_sim/gz-waves-models/worlds/waves.sdf"

cleanup() {
    echo "Cleaning up processes for session $SESSION..."
    tmux kill-session -t $SESSION 2>/dev/null
    pkill -9 -f "gz sim" 2>/dev/null
    pkill -9 -f "gzserver" 2>/dev/null
    pkill -9 -f "ardurover" 2>/dev/null
    pkill -9 -f "sim_vehicle.py" 2>/dev/null
    ros2 daemon stop >/dev/null 2>&1
}

# Ensure cleanup runs on manual exit (Ctrl+C)
trap cleanup EXIT SIGINT SIGTERM

for ((rep=1; rep<=REPETITIONS; rep++)); do
    echo "=================================================="
    echo "       STARTING FULL BATCH $rep OF $REPETITIONS   "
    echo "=================================================="

    for strategy in "${STRATEGIES[@]}"; do
        for cx in "${CURRENTS[@]}"; do
            for cy in "${CURRENTS[@]}"; do
                BAG_NAME="${BASE_WS}/bag_batch${rep}_${strategy}_cx_${cx}_cy_${cy}"

                # CHECK IF BAG OR COMPLETED RESULTS DIRECTORIES ALREADY EXIST
                if [ -d "$BAG_NAME" ] || [ -d "${BAG_NAME}_SUCCESS" ] || [ -d "${BAG_NAME}_TIMEOUT" ]; then
                    echo "--------------------------------------------------"
                    echo " [SKIP] Bag directory exists for Batch $rep | $strategy | X=$cx, Y=$cy. Skipping..."
                    echo "--------------------------------------------------"
                    continue
                fi

                echo "--------------------------------------------------"
                echo " RUNNING: Batch $rep | Strategy: $strategy | Current: X=$cx, Y=$cy"
                echo "--------------------------------------------------"

                # Generate runtime waves.sdf directly from template
                sed -e "s/\${CURRENT_X}/$cx/g" \
                    -e "s/\${CURRENT_Y}/$cy/g" \
                    "$TEMPLATE_PATH" > "$TARGET_SDF"
		SESSION_CX=$(echo "$cx" | tr '.' '_')
		SESSION_CY=$(echo "$cy" | tr '.' '_')

		SESSION="dock_${rep}_${strategy}_cx${SESSION_CX}_cy${SESSION_CY}"

                cleanup

                # 1. Gazebo Simulation
                tmux new-session -d -s $SESSION -n "Gazebo"
                tmux send-keys -t $SESSION:Gazebo "cd ${BASE_WS} && source install/setup.bash && source gazebo_exports.sh && ros2 launch move_blueboat launch_robot_simulation.launch.py" C-m
                sleep 5

                # 2. Detach Magnet
                tmux new-window -t $SESSION -n "MagnetDetach"
                tmux send-keys -t $SESSION:MagnetDetach "cd ${BASE_WS} && source install/setup.bash && ros2 topic pub --once /smallboat/magnet/detach std_msgs/msg/Empty \"{}\"" C-m

                # 3. SITL Instances (-N skips rebuild)
                tmux new-window -t $SESSION -n "SITL_Blueboat"
                tmux send-keys -t $SESSION:SITL_Blueboat "sim_vehicle.py -N -v Rover -f gazebo-rover --model JSON -l 55.99541530863445,-3.3010225004910683,0,0 --out=udp:127.0.0.1:14552 --add-param-file=/home/blueboat_sitl/SITL_Models/CustomModels/models/blueboat_with_tags/ardurover.parm --no-rebuild" C-m

                tmux new-window -t $SESSION -n "SITL_Smallboat"
                tmux send-keys -t $SESSION:SITL_Smallboat "sim_vehicle.py -N -v Rover -f gazebo-rover --model JSON -I1 -l 55.99539730863445,-3.3010225004910683,0,0 --add-param-file=/home/blueboat_sitl/SITL_Models/CustomModels/models/smallboat/ardurover.parm --out=udp:127.0.0.1:14562 --no-rebuild" C-m
                sleep 8

                # 4. MAVROS Nodes
                tmux new-window -t $SESSION -n "MAVROS_Blueboat"
                tmux send-keys -t $SESSION:MAVROS_Blueboat "source ${BASE_WS}/install/setup.bash && ros2 launch ardupilot_mavros_utils apm.launch.py fcu_url:='udp://:14552@' tgt_system:=1 namespace:=blueboat/mavros use_sim_time:=true" C-m

                tmux new-window -t $SESSION -n "MAVROS_Smallboat"
                tmux send-keys -t $SESSION:MAVROS_Smallboat "source ${BASE_WS}/install/setup.bash && ros2 launch ardupilot_mavros_utils apm.launch.py fcu_url:='udp://:14562@' tgt_system:=2 namespace:=smallboat/mavros use_sim_time:=true" C-m
                sleep 5

                # 5. Parameters & Control Nodes
                tmux new-window -t $SESSION -n "Params"
                tmux send-keys -t $SESSION:Params "source ${BASE_WS}/install/setup.bash && ros2 param set /smallboat/mavros/setpoint_velocity mav_frame BODY_NED && ros2 param set /blueboat/mavros/setpoint_velocity mav_frame BODY_NED" C-m

                tmux new-window -t $SESSION -n "Vision"
                tmux send-keys -t $SESSION:Vision "source ${BASE_WS}/install/setup.bash && cd ${BASE_WS}/src/catabot_docking2 && ros2 launch vision_pipeline.launch.py detector:=apriltag enable_recording:=false namespace:=smallboat/left use_camera:=false use_sim_time:=true" C-m

                tmux new-window -t $SESSION -n "MagnetBridge"
                tmux send-keys -t $SESSION:MagnetBridge "source ${BASE_WS}/install/setup.bash && cd ${BASE_WS}/src/catabot_docking2 && python3 magnet_bridge_node.py --ros-args -p use_sim_time:=true" C-m

                tmux new-window -t $SESSION -n "DockingNode"
                tmux send-keys -t $SESSION:DockingNode "source ${BASE_WS}/install/setup.bash && cd ${BASE_WS}/src/catabot_docking2/guided && python3 docking_magnet_two_markers.py --ros-args -p use_sim_time:=true" C-m

                tmux new-window -t $SESSION -n "GPSApproach"
                tmux send-keys -t $SESSION:GPSApproach "source ${BASE_WS}/install/setup.bash && cd ${BASE_WS}/src/catabot_docking2/guided && python3 gps_approach_node.py --ros-args -p use_sim_time:=true" C-m

                tmux new-window -t $SESSION -n "BlueboatStation"
                tmux send-keys -t $SESSION:BlueboatStation "source ${BASE_WS}/install/setup.bash && cd ${BASE_WS}/src/catabot_docking2/blueboat/ && python3 blueboat_station_node.py --ros-args -p use_sim_time:=true -p strategy:=$strategy -r __ns:=/blueboat" C-m

                # 6. ROS 2 Bag Recording
                tmux new-window -t $SESSION -n "BagRecord"
                tmux send-keys -t $SESSION:BagRecord "source ${BASE_WS}/install/setup.bash && ros2 bag record -o $BAG_NAME /blueboat/environment/global_current /blueboat/mavros/global_position/global /blueboat/mavros/global_position/compass_hdg /blueboat/dock_station/approach_pose /blueboat/dock_station/status /blueboat/mavros/state /blueboat/mavros/setpoint_velocity/cmd_vel /blueboat/mavros/imu/data /tag16/detections /tag36/detections /tf /tf_static /smallboat/left/resize/image_raw/compressed /electromagnet/command /electromagnet/state /smallboat/gps_approach_node/state /smallboat/apriltag_dock_controller/state /smallboat/mavros/global_position/global /smallboat/mavros/global_position/compass_hdg /smallboat/mavros/state /smallboat/mavros/setpoint_velocity/cmd_vel" C-m

                # 7. Execution Monitor
                echo "Waiting for /smallboat/gps_approach_node/state -> JOIN..."
                bash -c '
                    source /home/blueboat_sitl/gz_ws/install/setup.bash
                    ros2 topic echo --no-daemon /smallboat/gps_approach_node/state std_msgs/msg/String | grep -m 1 "JOIN"
                '

                echo "JOIN received. Starting ${TIMEOUT}s docking timer..."
                timeout ${TIMEOUT}s bash -c '
                    source /home/blueboat_sitl/gz_ws/install/setup.bash
                    ros2 topic echo --no-daemon /smallboat/apriltag_dock_controller/state std_msgs/msg/String | grep -m 1 "DOCKED"
                '

                RESULT=$?
                if [ $RESULT -eq 124 ]; then
                    echo "RESULT: TIMEOUT (Batch $rep | Strategy: $strategy | X=$cx, Y=$cy)"
                    mv "$BAG_NAME" "${BAG_NAME}_TIMEOUT" 2>/dev/null
                else
                    echo "RESULT: SUCCESS (Batch $rep | Strategy: $strategy | X=$cx, Y=$cy)"
                    mv "$BAG_NAME" "${BAG_NAME}_SUCCESS" 2>/dev/null
                fi

                cleanup
                sleep 3
            done
        done
    done
done
