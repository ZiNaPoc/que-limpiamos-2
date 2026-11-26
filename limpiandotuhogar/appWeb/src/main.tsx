import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import App from "./App";
import { CatalogoProvider } from "./data/CatalogoContext";
import { ClientesProvider } from "./data/ClientesContext";
import { TrabajadoresProvider } from "./data/TrabajadoresContext";
import "./index.css";

// SolicitudesProvider no va aquí: lo monta DashboardPage, para que las solicitudes
// solo se pidan al backend cuando ya hay sesión (antes se pedían también en la landing y el login).
createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <ClientesProvider>
      <TrabajadoresProvider>
        <CatalogoProvider>
          <App />
        </CatalogoProvider>
      </TrabajadoresProvider>
    </ClientesProvider>
  </StrictMode>,
);
