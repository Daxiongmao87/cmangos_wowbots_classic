# CMaNGOS WoWBots Classic

## Project Purpose

This project is an All-In-One server for the World of Warcraft Classic game. It includes the database application (MariaDB), the servers (mangosd and realmd), and an accessible website (cmangos-website).

## Instructions

1. Edit the `docker-compose.yml` file to your liking.
2. To start the server, run the following command in the terminal:
```sh
docker-compose up --build -d
```
3. After starting the server, new configuration files will be created in the `etc` directory. You can edit these files to your liking, but will require a restart of the server to apply changes:
```sh
docker-compose restart
```