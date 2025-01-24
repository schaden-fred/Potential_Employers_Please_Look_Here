# Feed Monitor
This is a generic bash script for monitoring the status of an inbound datafeed that interacts with a PostgreSQL database.  It should be run as a Cron job at regular intervals.  

On each run, it will check the database for signs that the process has failed.  (No new messages, or messages backing up in the queue and not being processed)
If it detects a failure, it will kill and restart the process, and set a flag to indicate that it has done this.
On the next run, if it still detects a failure, it will send an HTTP push to your monitoring system (Uptime Kuma in this example) which can then trigger an on-call alert.

