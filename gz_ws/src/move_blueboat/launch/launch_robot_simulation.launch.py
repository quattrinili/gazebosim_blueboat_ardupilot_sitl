from launch import LaunchDescription
from launch.actions import ExecuteProcess
from launch_ros.actions import Node

def generate_launch_description():
    return LaunchDescription([
        # Launch Gazebo simulation with environment variable
        ExecuteProcess(
            cmd=['env', 'LIBGL_ALWAYS_SOFTWARE=1', 'gz', 'sim', 'waves.sdf'],
            output='screen'
        ),

        # Launch the Gazebo-ROS bridge
        Node(
            package='ros_ign_bridge',
            executable='parameter_bridge',
            arguments=[
                '/model/blueboat/joint/motor_port_joint/cmd_thrust@std_msgs/msg/Float64@ignition.msgs.Double',
                '/model/blueboat/joint/motor_stbd_joint/cmd_thrust@std_msgs/msg/Float64@ignition.msgs.Double',
                '/model/blueboat/odometry@nav_msgs/msg/Odometry@ignition.msgs.Odometry',
                '/navsat@sensor_msgs/msg/NavSatFix@ignition.msgs.NavSat',
                # camera
                # '/camera@sensor_msgs/msg/Image@ignition.msgs.Image',
                # '/camera_info@sensor_msgs/msg/CameraInfo@ignition.msgs.CameraInfo',
                # lidar
                # '/laser_scan@sensor_msgs/msg/LaserScan@ignition.msgs.LaserScan',

                '/model/smallboat/joint/motor_port_joint/cmd_thrust@std_msgs/msg/Float64@ignition.msgs.Double',
                '/model/smallboat/joint/motor_stbd_joint/cmd_thrust@std_msgs/msg/Float64@ignition.msgs.Double',
                '/model/smallboat/odometry@nav_msgs/msg/Odometry@ignition.msgs.Odometry',
                '/smallboat/navsat@sensor_msgs/msg/NavSatFix@ignition.msgs.NavSat',
                # Smallboat Stereo Camera (Left)
                # '/smallboat/left/camera/image_raw@sensor_msgs/msg/Image@ignition.msgs.Image',
                '/smallboat/left/camera/camera_info@sensor_msgs/msg/CameraInfo@ignition.msgs.CameraInfo',
                
                # Smallboat Stereo Camera (Right)
                # '/smallboat/right/camera/image_raw@sensor_msgs/msg/Image@ignition.msgs.Image',
                # '/smallboat/right/camera/camera_info@sensor_msgs/msg/CameraInfo@ignition.msgs.CameraInfo',
                # lidar
                # '/smallboat/laser_scan@sensor_msgs/msg/LaserScan@ignition.msgs.LaserScan',

                '/smallboat/magnet/attach@std_msgs/msg/Empty@gz.msgs.Empty',
                '/smallboat/magnet/detach@std_msgs/msg/Empty@gz.msgs.Empty',

                '/model/blueboat/pose@tf2_msgs/msg/TFMessage@gz.msgs.Pose_V',
                '/model/blueboat/pose_static@tf2_msgs/msg/TFMessage[gz.msgs.Pose_V',

                '/model/smallboat/pose@tf2_msgs/msg/TFMessage[gz.msgs.Pose_V',
                '/model/smallboat/pose_static@tf2_msgs/msg/TFMessage[gz.msgs.Pose_V',
            ],
            parameters=[
            # Force /tf_static to use transient_local durability to satisfy ROS 2 requirements
                {'qos_overrides./tf_static.publisher.durability': 'transient_local'}
            ],
            remappings=[
                # Remap Gazebo pose topics directly to ROS 2 standard TF topics
                ('/model/blueboat/pose', '/tf'),
                ('/model/blueboat/pose_static', '/tf_static'),
                ('/model/smallboat/pose', '/tf'),
                ('/model/smallboat/pose_static', '/tf_static'),
            ],
            output='screen'
        ),
        Node(
            package='ros_ign_image',
            executable='image_bridge',
            arguments=[
                # '/camera', # Blueboat camera
                '/smallboat/left/camera/image_raw' # Smallboat camera
            ],
            output='screen'
        ),
        # Optionally, launch your ROS 2 node if you have a custom node for additional logic
        # Node(
        #     package='move_blueboat',
        #     executable='robot_controller',
        #     output='screen',
        #     name='robot_controller'
        # ),
    ])

