#!/usr/bin/env bash
chown containerdb /var/run/docker.sock
docker pull containerdb/backup-restore
docker pull postgres:9.6
docker pull mysql:5.7
docker pull tutum/redis

# Setup for the first time
if ! containerdb config:get DATABASE_URL 2>/dev/null; then
  # Get the configs from the user. This may not work, testing now
  echo ''
  echo 'Lets configure Container DB'
  echo ''
  HOST_IP=`curl ipinfo.io/ip 2>/dev/null;`

  while [[ -z "$HOST_NAME" ]]
  do
    read -p "Hostname: " -e -i $HOST_IP HOST_NAME
  done
  echo ''

  echo 'And now lets setup your first user'
  while [[ -z "$ADMIN_EMAIL" ]]
  do
    read -p "Admin Email: " -e ADMIN_EMAIL
  done

  while [[ -z "$ADMIN_PASSWORD" ]]
  do
    read -p "Admin Password: " -e ADMIN_PASSWORD
  done

  echo ''
  echo 'Please enter your AWS credentials for backups'

  while [[ -z "$AWS_SECRET_KEY" ]]
  do
    read -p "AWS_SECRET_KEY: " -e AWS_SECRET_KEY
  done

  while [[ -z "$AWS_ACCESS_TOKEN" ]]
  do
    read -p "AWS_ACCESS_TOKEN: " -e AWS_ACCESS_TOKEN
  done

  while [[ -z "$AWS_BUCKET_NAME" ]]
  do
    read -p "AWS_BUCKET_NAME: " -e AWS_BUCKET_NAME
  done

  echo 'Thanks... carrying on'
  echo ''

  # Create the Postgres Container
  DB_PORT=8474
  DB_USERNAME='postgres'
  DB_PASSWORD=`date +%s | sha256sum | base64 | head -c 32 ; echo`
  DB_CONTAINER_ID=`docker create --name containerdb_db -p $DB_PORT:5432 -e POSTGRES_PASSWORD=$DB_PASSWORD -e POSTGRES_USER=$DB_USERNAME postgres`

  # Start the DB Container
  docker start containerdb_db
  sleep 5 # @todo wait for the DB container to start

  sudo containerdb config:set AWS_ACCESS_TOKEN=$AWS_ACCESS_TOKEN
  sudo containerdb config:set AWS_SECRET_KEY=$AWS_SECRET_KEY
  sudo containerdb config:set AWS_BUCKET_NAME=$AWS_BUCKET_NAME
  sudo containerdb config:set DATABASE_URL="postgres://$DB_USERNAME:$DB_PASSWORD@127.0.0.1:$DB_PORT"
  sudo containerdb config:set HOST=$HOST_NAME
  sudo containerdb scale web=1
  sudo service containerdb restart

  sudo containerdb run rails db:create db:migrate
  sudo containerdb run rails r "Service.create!(locked: true, service_type: :postgres, name: 'containerdb', port: $DB_PORT, container_id: '$DB_CONTAINER_ID', environment_variables: { 'POSTGRES_PASSWORD' => '$DB_PASSWORD', 'POSTGRES_USER' => '$DB_USERNAME'})"
  sudo containerdb run rails r "User.create!(email: '$ADMIN_EMAIL', password: '$ADMIN_PASSWORD')"
  sudo containerdb run rails r "Service.where(name: 'containerdb', locked: true).first.backup(inline: true)"

  cat > /etc/nginx/sites-available/default <<EOF
server {
  listen 80;
  location / {
    proxy_pass http://localhost:6000;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_set_header Host \$http_host;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_redirect off;
  }
}
EOF

  sudo service nginx restart
else
  sudo containerdb run rails r "Service.where(name: 'containerdb', locked: true).first.backup(inline: true)"
  sudo containerdb run rails db:migrate
  sudo service containerdb restart
fi

echo ''
echo "Visit http://$(sudo containerdb config:get HOST)"
