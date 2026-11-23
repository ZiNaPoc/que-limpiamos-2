import { Router } from "express";
import * as galaxiasController from "../controller/galaxias.controller";

const router = Router();

router.get('/', galaxiasController.getAll);
router.get('/:id', galaxiasController.getById);
router.post('/', galaxiasController.create);

export default router;