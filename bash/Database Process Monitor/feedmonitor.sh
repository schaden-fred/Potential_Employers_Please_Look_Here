#!/bin/sh

# This script needs the database hostname, username, and password as variables.  Best practice is to use a secrets manager to populate the variables when this script runs.  Do that here.
#$DATABASE_USERNAME=
#$DATABASE_PASSWORD=
#$DATABASE_HOST=

# Get settings from a table in the database.  This allows the settings to be adjusted on a per-site basis.
# Number of allowable unprocessed messages in the inbound queue.
max_inbound_data_backlog=$(PGPASSWORD=$DATABASE_PASSWORD psql -t -h $DATABASE_HOST -U $DATABASE_USERNAME -c "select max_inbound_data_backlog from dbprocessmonitorsettings where is_enabled = 't' limit 1;"|xargs)
# If we don't get a message in X seconds, we will attempt to reset the feed.  We don't alert on this value, because sometimes feeds go quiet because there's no data changing.
max_seconds_since_last_message=$(PGPASSWORD=$DATABASE_PASSWORD psql -t -h $DATABASE_HOST -U $DATABASE_USERNAME -c "select max_seconds_since_last_message from dbprocessmonitorsettings where is_enabled = 't' limit 1;"|xargs)
# If we go this many seconds without getting a new message, we send an alert.
max_seconds_since_last_message_alert=$(PGPASSWORD=$DATABASE_PASSWORD psql -t -h $DATABASE_HOST -U $DATABASE_USERNAME -c "select max_seconds_since_last_message_alert from dbprocessmonitorsettings where is_enabled = 't' limit 1;"|xargs)
# Checks to see if a feedmonitor config is enabled.
feedmonitor_enabled=$(PGPASSWORD=$DATABASE_PASSWORD psql -t -h $DATABASE_HOST -U $DATABASE_USERNAME -c "select count(1) from dbprocessmonitorsettings where is_enabled = 't';"|xargs)
#Gets the URL that is used to report back to the monitoring system.
monitoring_url=$(PGPASSWORD=$DATABASE_PASSWORD psql -t -h $DATABASE_HOST -U $DATABASE_USERNAME -c "select monitoring_url from dbprocessmonitorsettings where is_enabled = 't' limit 1;"|xargs)

# Static config settings.
# Seconds to wait after a dead feed process was started before continuing the test.
dead_process_pause=60 
# Seconds to wait after killing the feed before issuing a kill -9
kill9_pause=120
# Seconds to wait after killing the feed before restarting itå
restart_feed_pause=60
# Location of a temp file that is used as a flag in later processing.
data_backlog_flag=/tmp/data_backlog.flag
# Location of a temp file that is used as a flag in later processing.
no_new_messages_flag=/tmp/no_new_messages.flag



# Gathering data on the feed status
lowercase_server_environment=$(echo $SERVER_ENVIRONMENT | tr '[:upper:]' '[:lower:]') # Convert $SERVER_ENVIRONMENT variable to lowercase, eliminiating case sensitivity issues.
feed_enabled=$(PGPASSWORD=$DATABASE_PASSWORD psql -t -h $DATABASE_HOST -U $DATABASE_USERNAME -c "select count(1) from feedconfig where enabled = 't';"|xargs)
data_backlog=$(PGPASSWORD=$DATABASE_PASSWORD psql -t -h $DATABASE_HOST -U $DATABASE_USERNAME -c "select count(1) from inbound_queue where processed_time is null;"|xargs)
seconds_since_last_message=$(PGPASSWORD=$DATABASE_PASSWORD psql -t -h $DATABASE_HOST -U $DATABASE_USERNAME -c "select trunc(extract(epoch from(CURRENT_TIMESTAMP - staged_time))) as age from inbound_queue where id = (select max(id) from inbound_queue);"|xargs)

# Get PIDs of the feed processes.  If any are not running, they will be started in this step.
# The -o flag is used with prgep because some feed tasks create child processes.
# By getting the oldest pid, we should always get the parent process pid.
process_1_pid=$(pgrep -f "python path/to/process_1.py")
process_2_pid=$(pgrep -f "python path/to/process_2.py")
process_3_pid=$(pgrep -f "python path/to/process_3.py")
process_4_pid=$(pgrep -f "python path/to/process_4.py")

# Initialize variables
dead_feed_process='false'

#If needed, change to the correct working directory before beginning.
cd /code

# Define a function to restart one or more processes.
restart_feed () {
        curl -o /dev/null -sk "$monitoring_url?status=up&msg=Restarting&ping="
        echo "Stopping via kill."
        if [ -z "$process_1_pid" ]; then echo "No PID to stop"; else kill $process_1_pid; fi
        if [ -z "$process_2_pid" ]; then echo "No PID to stop"; else kill $process_2_pid; fi
        if [ -z "$process_3_pid" ]; then echo "No PID to stop"; else kill $process_3_pid; fi
        if [ -z "$process_4_pid" ]; then echo "No PID to stop"; else kill $process_4_pid; fi
        sleep $kill9_pause
        echo "Stopping via kill -9"
        if [ -z "$process_1_pid" ]; then echo "No PID to stop"; else kill -9 $process_1_pid; fi
        if [ -z "$process_2_pid" ]; then echo "No PID to stop"; else kill -9 $process_2_pid; fi
        if [ -z "$process_3_pid" ]; then echo "No PID to stop"; else kill -9 $process_3_pid; fi
        if [ -z "$process_4_pid" ]; then echo "No PID to stop"; else kill -9 $process_4_pid; fi
        sleep $restart_feed_pause
        python path/to/process_1.py &
        python path/to/process_2.py &
        python path/to/process_3.py &
        python path/to/process_4.py &
        echo "Feed restarted."
        echo ""
        exit
}


# Main code.  Begin your debugging here.
# If there isn't an active feed monitor config, do nothing.
if [ "$feedmonitor_enabled" -eq 0 ]
then
        echo "Feed monitoring is not enabled."
        exit
fi

if [ "$feed_enabled" -gt 0 ] # Check if feed is enabled.  Any number greater than 0 indicates one or more feed configs exist.
then
        echo ""
        echo ""
        echo "- $(date) -- Feed Status for $SERVER_NAME ----------"
        echo "- process_1_pid = $process_1_pid"
        echo "- process_2_pid = $process_2_pid"
        echo "- process_3_pid = $process_3_pid"
        echo "- process_4_pid = $process_4_pid"
        echo "- feed_enabled = $feed_enabled"
        echo "- seconds_since_last_message = $seconds_since_last_message"
        echo "- data_backlog = $data_backlog"

        # Start processes if they're not running. Wait 2 seconds to let each process start.
        if [ -z "$process_1_pid" ]
        then
                echo "process_1.py is down.  Starting it."
                python path/to/process_1.py &
                dead_feed_process="true"
                sleep 2
                process_1_pid=$(pgrep -o -f "path/to/process_1.py")
        fi
        if [ -z "$process_2_pid" ]
        then
                echo "process_2.py is down.  Starting it."
                python path/to/process_2.py &
                dead_feed_process="true"
                sleep 2
                process_1_pid=$(pgrep -o -f "path/to/process_2.py")
        fi
        if [ -z "$process_3_pid" ]
        then
                echo "process_3.py is down.  Starting it."
                python path/to/process_3.py &
                dead_feed_process="true"
                sleep 2
                process_1_pid=$(pgrep -o -f "path/to/process_3.py")
        fi
        if [ -z "$process_4_pid" ]
                echo "process_4.py is down.  Starting it."
                python path/to/process_4.py &
                dead_feed_process="true"
                sleep 2
                process_1_pid=$(pgrep -o -f "path/to/process_4.py")
        fi

        # A feed process died and had to be restarted.  Pause before continuing with the check.
        if $dead_feed_process == 'true'
                then echo "Pausing $dead_process_pause seconds before continuing the feed test."
                curl -o /dev/null -sk "$monitoring_url?status=up&msg=Restarted_A_Dead_Process&ping="
                sleep $dead_process_pause
        fi

        # This section handles things if messages are backing up in the inbound queue.
        if [ "$data_backlog" -gt "$max_inbound_data_backlog" ]; then # Check if feed messages are backing up in queue
                echo "DATA_BACKUP: $data_backlog messages in queue."
                #Check if data_backlog flag is set
                if test -f $data_backlog_flag; then
                        #echo "The data_backlog_flag is set.  On my last run, I tried to fix the feed."
                        #echo "I'm checking to see if the feed is processing.  If it is not, I will alert."
                        # Check if the feed's still moving by getting last_processed_raw_message id, waiting 30 seconds, then checking it again.
                        last_processed_raw_message=$(PGPASSWORD=$DATABASE_PASSWORD psql -t -h $DATABASE_HOST -U $DATABASE_USERNAME -c " select min(id) from inbound_queue where processed_outcome is null;"|xargs);
                        sleep 30
                        last_processed_raw_message1=$(PGPASSWORD=$DATABASE_PASSWORD psql -t -h $DATABASE_HOST -U $DATABASE_USERNAME -c " select min(id) from inbound_queue where processed_outcome is null;"|xargs);
                        if [ "$last_processed_raw_message" -eq "$last_processed_raw_message1" ]
                        then
                                #echo "Feed has been restarted and the issue is persisting."
                                if [ "$lowercase_server_environment" = "prod" ]  #[[ "$lowercase_server_environment" = "prod" || "$SERVER_NAME" != *"test"* ]]
                                then
                                        echo "PROD ALERT: $(date) The inbound_queue table for $SERVER_NAME contains $data_backlog unprocessed messages."
                                        curl -o /dev/null -sk "$monitoring_url?status=down&msg=data_backlog&ping="
                                else
                                        echo "NON-PROD ALERT: $(date) The inbound_queue table for $SERVER_NAME contains $data_backlog unprocessed messages."
                                        curl -o /dev/null -sk "$monitoring_url?status=down&msg=data_backlog&ping="
                                fi
                                exit
                        else
                                echo "INFO: $(date) I fixed an data_backlog for $SERVER_NAME."
                        fi
                else
                        #echo "The data_backlog_flag is not set.  This problem just started happening."
                        #echo "I'm checking to see if the feed is processing.  If it is not, I will restart it."
                        # Check if the feed's still moving by getting last_processed_raw_message id, waiting 30 seconds, then checking it again.
                        last_processed_raw_message=$(PGPASSWORD=$DATABASE_PASSWORD psql -t -h $DATABASE_HOST -U $DATABASE_USERNAME -c " select min(id) from inbound_queue where processed_outcome is null;"|xargs);
                        sleep 30
                        last_processed_raw_message1=$(PGPASSWORD=$DATABASE_PASSWORD psql -t -h $DATABASE_HOST -U $DATABASE_USERNAME -c " select min(id) from inbound_queue where processed_outcome is null;"|xargs);
                        if [ "$last_processed_raw_message" -eq "$last_processed_raw_message1" ]; then
                                touch $data_backlog_flag
                                echo "WARNING: $(date) The feed is not processing. Restarting feed."
                                restart_feed
                        else
                                echo "INFO: $(date) The feed is processing.  No action required."
                                curl -o /dev/null -sk "$monitoring_url?status=up&msg=Feed_OK&ping="
                        fi
                        exit
                fi
        else
                [ -e $data_backlog_flag ] && rm $data_backlog_flag
        fi
        #
        #This section handles things if we're not receiving feed messages.
        #
        if [ "$seconds_since_last_message" -gt "$max_seconds_since_last_message" ]; then # Check the age of the most recent received message.
                echo "NO_NEW_INBOUND_MESSAGES: $seconds_since_last_message seconds since last message was received."
                if test -f $no_new_messages_flag; then
                        #echo "The no_new_messages_flag is set.  On my last run, I tried to fix the feed."
                        #echo "The feed has been restarted and the issue is persisting."
                        if [ "$lowercase_server_environment" = "prod" ]  #[[ "$lowercase_server_environment" = "prod" || "$SERVER_NAME" != *"test"* ]]
                        then
                                if [ "$seconds_since_last_message" -gt "$max_seconds_since_last_message_alert" ]
                                then
                                        echo "PROD ALERT: $(date) The feed for $SERVER_NAME has not received a message in $seconds_since_last_message seconds."
                                        curl -o /dev/null -sk "$monitoring_url?status=down&msg=No_New_Messages_Received&ping="
                                else
                                        echo "WARNING: $(date) Not receiving messages after feed reset.  Waiting to reach alert threshold."
                                        curl -o /dev/null -sk "$monitoring_url?status=up&msg=No_New_Messages_Received&ping="
                                fi
                        else
                                if [ "$seconds_since_last_message" -gt "$max_seconds_since_last_message_alert" ]
                                then
                                        echo "NON-PROD ALERT: $(date) The feed for $SERVER_NAME has not received a message in $seconds_since_last_message seconds."
                                        curl -o /dev/null -sk "$monitoring_url?status=down&msg=No_New_Messages_Received&ping="
                                else
                                        echo "WARNING: $(date) Not receiving messages after feed reset.  Waiting to reach alert threshold."
                                        curl -o /dev/null -sk "$monitoring_url?status=up&msg=No_New_Messages_Received&ping="
                                fi
                        fi
                        exit
                else
                        touch $no_new_messages_flag
                        echo "WARNING: $(date) The feed is not receiving messages. Restarting feed."
                        restart_feed
                fi
        else
                if test -f $no_new_messages_flag; then
                        echo "INFO: $(date) I fixed a failed listener for $SERVER_NAME."
                fi
                [ -e $no_new_messages_flag ] && rm $no_new_messages_flag
        fi
        echo "INFO: $(date) Feed is healthy"
        curl -o /dev/null -sk "$monitoring_url?status=up&msg=Feed_OK&ping="
else
        echo "INFO: $(date) Datafeed is disabled."
        curl -o /dev/null -sk "$monitoring_url?status=up&msg=Feed_Disabled&ping="
fi
