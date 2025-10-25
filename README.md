# 🏦 KipuBank V2  

![Solidity](https://img.shields.io/badge/Solidity-0.8.30-blue.svg?logo=ethereum)  
![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)  
![Status](https://img.shields.io/badge/status-deployed-success.svg)  
![Network](https://img.shields.io/badge/network-Sepolia-purple.svg)  

**KipuBankV2** es un **banco descentralizado en Ethereum** que permite a los usuarios **depositar y retirar fondos tanto en Ether (ETH) como en tokens USDC**, con seguridad reforzada mediante **OpenZeppelin** y validación de límites configurables.  

Esta versión presenta una arquitectura más sólida, mejor eficiencia en gas, y un modelo dual de bóvedas por usuario — una para **ETH** y otra para **USDC**.  

---

## ✨ Resumen de mejoras en la versión 2  

| Área | Mejora | Motivo |
|------|---------|--------|
| **Multi-activo** | Soporte para depósitos y retiros en **ETH** y **USDC** | Expande la funcionalidad del banco a activos ERC20. |
| **Seguridad** | Uso de `ReentrancyGuard` y patrón CEI | Previene ataques de reentrancy. |
| **Control administrativo** | Integración de `Ownable` y `Pausable` | Permite pausar operaciones ante mantenimiento o emergencias. |
| **Eficiencia** | Reemplazo de `require()` por `custom errors` | Reducción significativa en consumo de gas. |
| **Auditoría** | Nuevos eventos: `DepositoETH`, `DepositoUSDC`, `RetiroETH`, `RetiroUSDC` | Mejor trazabilidad en exploradores y logs. |

---

## ⚙️ Arquitectura  

Cada usuario posee **una bóveda que se bifurca en dos**, una para **ETH** y otra para **USDC**, gestionadas mediante un `mapping` anidado:

```solidity
   mapping (address token => mapping (address titular => uint monto)) private s_cuentasMultiToken;
```

Los límites globales (`bankCap`) y de retiro (`umbral`) se definen en el **constructor** al momento del despliegue.  

---

## 📜 Funcionalidades principales  

| Función | Tipo | Descripción |
|----------|------|-------------|
| `depositarETH()` | `payable` | Permite depositar Ether en la bóveda personal del usuario, verificando el límite global. |
| `retirarETH(uint256 monto)` | `external` | Retira Ether si el monto no supera el umbral ni el saldo personal. |
| `depositarUSDC(uint256 monto)` | `external` | Deposita tokens USDC al contrato usando la interfaz `IERC20`. |
| `retirarUSDC(uint256 monto)` | `external` | Envía USDC de vuelta al usuario, respetando umbral y saldo. |
| `verBovedaETH()` | `view` | Devuelve el saldo ETH del usuario. |
| `verBovedaUSDC()` | `view` | Devuelve el saldo USDC del usuario. |
| `verTotalContrato()` | `view` | Devuelve el total combinado de ETH y USDC dentro del contrato. |

---

## 🚀 Despliegue (Remix + MetaMask)  

1. Abrí [Remix IDE](https://remix.ethereum.org/).  
2. Compilá el contrato `KipuBank.sol` con la versión **0.8.30**.  
3. En la pestaña **Deploy & Run Transactions**:  
   - Seleccioná `Injected Provider - MetaMask`.  
   - Conectate a la red **Sepolia**.  
4. Ingresá los parámetros del constructor:  
   - `_bankCap`: límite global (en wei).  
   - `_umbral`: límite máximo de retiro (en wei).  
   - `_tokenUSDC`: dirección del contrato USDC en la red elegida.
   - `_owner`: dirección del dueño del contrato.
   - `_feed`: dirección del óraculo que proveé los data feeds
5. Hacé clic en **Deploy** y confirmá la transacción en MetaMask.  

---

## 💻 Interacción básica  

| Acción | Descripción |
|--------|--------------|
| 💰 **Depositar ETH** | Ejecutar `depositarETH()` e ingresar el monto en `Value` (ej: `1 ether`). |
| 💵 **Depositar USDC** | Llamar `depositarUSDC(uint monto)` (el usuario debe haber hecho `approve` previamente al contrato). |
| 💸 **Retirar ETH** | Llamar `retirarETH(uint monto)` indicando el monto en wei. |
| 💳 **Retirar USDC** | Llamar `retirarUSDC(uint monto)` para recibir los tokens en tu wallet. |
| 📊 **Consultar saldos** | Usar `verBovedaETH()` o `verBovedaUSDC()`. |

---

## 🛡️ Seguridad y control  

KipuBankV2 aplica un enfoque de **seguridad multicapa** basado en buenas prácticas DeFi y librerías de OpenZeppelin:

- 🔐 **ReentrancyGuard**: bloquea ataques de reentrancy en funciones críticas.  
- ⚙️ **Patrón CEI**: actualiza el estado antes de transferir fondos.  
- 🚫 **Pausable**: permite suspender depósitos y retiros temporalmente ante mantenimiento o auditoría.  
- 🧾 **Custom Errors**: revertencias más descriptivas y eficientes.  
- 🪪 **Ownable**: el deployer mantiene control sobre operaciones administrativas.  

---

## ⚖️ Decisiones de diseño y trade-offs  

| Decisión | Ventaja | Trade-off |
|-----------|----------|------------|
| Soporte dual (ETH / USDC) | Flexibilidad y adopción más amplia. | Incrementa la complejidad de mantenimiento. |
| Uso de `Ownable` | Control total sobre pausas y emergencias. | Introduce un nivel mínimo de centralización. |
| `Pausable` para mantenimiento | Permite actualizaciones o auditorías sin pérdida de fondos. | Durante el mantenimiento, los usuarios no pueden operar. |
| ReentrancyGuard de OpenZeppelin | Previene exploits críticos. | Leve aumento de gas (~150 unidades por función protegida). |
| Custom errors | Ahorro de gas y mensajes más claros. | Algunas herramientas antiguas no los muestran correctamente. |
| Límite `bankCap` y `umbral` | Control de flujo y riesgo. | Requiere calibración precisa según el entorno. |

---

## 🌐 Contrato verificado  

📍 **Dirección (Sepolia) y vista en el buscador de bloques:**  
[`0x89C97CEE83627F36e8344AB278B62E7a21C45796`](https://sepolia.etherscan.io/address/0x89C97CEE83627F36e8344AB278B62E7a21C45796)

---

## ⚖️ Licencia  

Este proyecto está bajo licencia [MIT](https://opensource.org/licenses/MIT).  
© 2025 — Desarrollado por **Facundo Alejandro Caniza** 🧠💎  

---

> 💬 *“La confianza no se delega, se codifica.” — KipuBankV2*
