# CMaNGOS WoWBots Classic

## Project Purpose

This project is an All-In-One server for the World of Warcraft Classic game. It includes the database application (MariaDB), the servers (mangosd and realmd), and an accessible website (cmangos-website).

## Instructions
1. Extract the **contents** of your World of Warcraft 1.12.1 client archive into the client directory.
1. Copy `.env.template` to `.env` and edit to your liking.
    1. The template's defaults are configured for WoW Classic. If that is your goal, no edits are needed.
1. To start the server, run the following command in the terminal:
```sh
docker-compose up --build -d
```
1. After starting the server, new configuration files will be created in the `etc` directory. You can edit these files to your liking, but will require a restart of the server to apply changes:
```sh
docker-compose restart
```
