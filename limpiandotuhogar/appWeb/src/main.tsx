import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import App from "./App";
import "./index.css";

// Los datos del panel salen del backend real (docs/backend/27). SolicitudesProvider y PermisosProvider
// los monta DashboardPage, para pedir datos solo cuando ya hay sesión.
createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <App />
  </StrictMode>,
);
