import "dotenv/config";

import express from "express";
import cors from "cors";
import loginRoutes from "./routes/login.routes";
import galaxiasRoutes from "./routes/galaxias.routes";
import hoyoNegroRoutes from "./routes/hoyo_negro.routes";
import {
    manejarErrores,
    rutaNoEncontrada,
} from "./middleware/error.middleware";

const origenesPermitidos = (process.env.CORS_ORIGINS ?? "http://localhost:5173" )
    .split(",")
    .map((o) => o.trim());

const app = express();

app.use(express.json());

app.use(
    cors({
        origin: origenesPermitidos,
        credentials: true,
    }),
);

app.get("/health", (_req, res) => {
    res.json({ status: "ok" });
});

app.use(loginRoutes);
app.use("/galaxias", galaxiasRoutes);
app.use("/hoyo-negro", hoyoNegroRoutes);

app.use(rutaNoEncontrada);
app.use(manejarErrores);

export default app;