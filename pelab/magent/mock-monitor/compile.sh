g++ -o udpmon udpmon.cc ../TSThroughputSensor.o ../CircularTraffic.o ../Command.o ../Connection.o ../Decayer.o ../DelaySensor.o ../DirectInput.o ../EwmaThroughputSensor.o ../KernelTcp.o ../LeastSquaresThroughput.o ../MaxDelaySensor.o ../MinDelaySensor.o ../PacketSensor.o ../Sensor.o ../SensorList.o ../StateSensor.o ../ThroughputSensor.o ../Time.o ../TrivialCommandOutput.o ../lib.o ../log.o ../saveload.o -lm -lpcap
