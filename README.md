# CMaNGOS WoWBots Classic

## Project Purpose

This project is an All-In-One server for the World of Warcraft Classic game. It includes the database application (MariaDB), the servers (mangosd and realmd), and an accessible website (cmangos-website).

## Instructions
1. Extract the **contents** of your World of Warcraft 1.12.1 client archive into the client directory.
1. Make a copy of `docker-compose.template.yaml`, rename to `docker-compose.yaml`, and edit to your liking.
1. Make a copy of `.env.template`, rename to `.env`, and edit to your liking.
    - The template has sensible defaults for running WoW Classic. If that's your goal, you do not need to edit it.
1. To start the server, run the following command in the terminal:
```sh
docker-compose up --build -d
```
1. After starting the server, new configuration files will be created in the `etc` directory. You can edit these files to your liking, but will require a restart of the server to apply changes:
```sh
docker-compose restart
```
