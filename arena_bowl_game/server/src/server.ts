import { Server, Room, Client } from "@colyseus/core";
import { WebSocketTransport } from "@colyseus/ws-transport";
import { BattleRoom } from "./BattleRoom";
import cors from "cors";
import express from "express";

/**
 * Конфигурация сервера
 */
const SERVER_CONFIG = {
  port: parseInt(process.env.PORT || "2567"),
  publicAddress: process.env.PUBLIC_ADDRESS || "localhost",
};

/**
 * Создание и запуск Colyseus сервера
 */
async function startServer(): Promise<void> {
  console.log("Starting Arena Bowl Game Server...");
  
  // Создаём Express приложение для health checks и статики
  const app = express();
  app.use(cors());
  app.get("/health", (req, res) => {
    res.json({ status: "ok", uptime: process.uptime() });
  });
  
  // Создаём WebSocket транспорт
  const transport = new WebSocketTransport({
    server: app,
  });
  
  // Создаём Colyseus сервер
  const gameServer = new Server({
    transport,
    greet: true,
  });
  
  // Регистрируем комнату BattleRoom
  gameServer.define("battle_room", BattleRoom)
    .enableRealtimeListing()
    .setMaxClients(4);
  
  // Обработка ошибок
  process.on("uncaughtException", (err) => {
    console.error("Uncaught Exception:", err);
  });
  
  process.on("unhandledRejection", (err) => {
    console.error("Unhandled Rejection:", err);
  });
  
  // Запуск сервера
  try {
    await gameServer.listen(SERVER_CONFIG.port);
    console.log(`✅ Server listening on ws://${SERVER_CONFIG.publicAddress}:${SERVER_CONFIG.port}`);
    console.log(`📊 Health check: http://localhost:${SERVER_CONFIG.port}/health`);
    console.log(`🎮 Room listing: ws://${SERVER_CONFIG.publicAddress}:${SERVER_CONFIG.port}/matchmake/`);
  } catch (e) {
    console.error("Failed to start server:", e);
    process.exit(1);
  }
}

// Запуск
startServer().catch(console.error);
