#!/bin/bash
set -e

# Remove a potentially pre-existing server.pid for Rails.
rm -f /code/tmp/pids/server.pid

echo "ENV: $RAILS_ENV"
if [[ "$RAILS_ENV" != "" && "$RAILS_ENV" != "development" ]]
then
  ./ecs-deployment-script.sh
fi

# Then exec the container's main process (what's set as CMD in the Dockerfile)
exec "$@"
