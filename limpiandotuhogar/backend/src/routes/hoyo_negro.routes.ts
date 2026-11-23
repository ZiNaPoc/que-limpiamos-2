import { Router } from "express";
import * as hoyoNegroController from "../controller/hoyo_negro.controller";

const router = Router();

router.get("/", hoyoNegroController.getAll); // ?cliente_id=1 o ?trabajador_id=2
router.get("/disponibles", hoyoNegroController.getDisponibles); // antes de "/:id"
router.get("/:id", hoyoNegroController.getById);
router.post("/", hoyoNegroController.create);
router.patch("/:id/aceptar", hoyoNegroController.aceptar);

export default router;