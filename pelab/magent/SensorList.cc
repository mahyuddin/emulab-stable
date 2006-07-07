// SensorList.cc

#include "lib.h"
#include "SensorList.h"

using namespace std;

SensorList::SensorList()
{
    tail = NULL;
    // Dependency = NULL here
}

SensorList::SensorList(SensorList const & right)
{
    *this = right;
}

SensorList & SensorList::operator=(SensorList const & right)
{
    if (this != &right)
    {
        if (right.head.get() != NULL)
        {
            head = right.head->clone();
            tail = ;
        }
        else
        {
            head.reset(NULL);
            tail = NULL;
        }
        // Copy dependency pointers here.
    }
}

void SensorList::addSensor(SensorCommand const & newSensor)
{
    // Add dependency type demux here.
    switch(newSensor.type)
    {
    default:
        logWrite(ERROR,
                 "Incorrect sensor type (%d). Ignoring add sensor command.",
                 newSensor.type);
        break;
    }
}

Sensor * SensorList::getHead(void)
{
    return head.get();
}

void pushSensor(std::auto_ptr<Sensor> newSensor)
{
    if (tail != NULL)
    {
        tail->addNode(newSensor);
    }
    else
    {
        head = newSensor;
        tail = head.get();
    }
}

// Add individual pushSensor functions here.

