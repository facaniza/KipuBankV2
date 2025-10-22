# 🏦 KipuBank  

![Solidity](https://img.shields.io/badge/Solidity-0.8.30-blue.svg?logo=ethereum)  ![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)  ![Status](https://img.shields.io/badge/status-active-success.svg)  

**KipuBank** es un contrato inteligente de Ethereum que funciona como un **banco descentralizado en blockchain**.  
Permite a los usuarios **depositar y retirar Ether** en una bóveda personal, respetando reglas de seguridad y límites configurables.  

---

## ✨ Features  

- 📥 **Depósitos seguros** → cada usuario tiene su propia bóveda.  
- 💸 **Retiros limitados** → con umbral declarado en el deploy y verificación de saldo.  
- 📊 **Estadísticas internas** → número de depósitos, retiros y total de Ether en el contrato.  
- 🚨 **Custom Errors** → manejo de errores más eficiente en gas.  
- 🔎 **Eventos de auditoría** → depósitos y retiros registrados on-chain.  

---

## 📜 Funcionalidades principales  

| Función                  | Tipo     | Descripción |
|---------------------------|----------|-------------|
| `depositarEnBoveda()`    | `payable` | Permite depositar Ether en la bóveda del titular (con verificación de `bankCap`). |
| `retirarDeBoveda(uint)`  | `external` | Retira fondos de la bóveda, siempre que no supere el `umbral` ni el saldo disponible. |
| `verBoveda()`            | `view`   | Devuelve el saldo actual en la bóveda del `msg.sender`. |
| `verTotalContrato()`     | `view`   | Devuelve el saldo total del contrato. |
| `verTotalDepositos()`    | `view`   | Devuelve el numero de depositos hechos en el contrato. |
| `verTotalRetiros()`      | `view`   | Devuelve el numero de retiros hechos en el contrato. |

---

## ⚙️ Cómo desplegar KipuBank en Remix  

Este proyecto está listo para ser desplegado por **cualquier persona** usando [Remix IDE](https://remix.ethereum.org/).  
No necesitás instalar nada localmente, solo tener **MetaMask** configurado en tu navegador y un poco de ETH de prueba en una testnet como **Sepolia**.  

---

### 🔧 Requisitos previos  

1. **Navegador con [MetaMask](https://metamask.io/)** instalado.  
2. Conectarte a una testnet de Ethereum (ej: Sepolia).  
3. Conseguir ETH de prueba en un faucet:  
   - [Sepolia Faucet oficial](https://sepoliafaucet.com/)  
   - [Alchemy Faucet](https://www.alchemy.com/faucets/ethereum-sepolia)  

---

### 🚀 Pasos para desplegar  

1. Abre [Remix IDE](https://remix.ethereum.org/).  
2. En la barra arriba a la derecha, ve a sección de **Github** y seleccioná la opción de **Clone**. 
3. Copia y pega la URL del repositorio de este contrato.
4. Remix cargará el código del contrato en tu espacio de trabajo.  
5. Abre el archivo `KipuBank.sol`.  
6. Compílalo desde la pestaña **Solidity Compiler** (versión `0.8.30`).  
7. Ve a la pestaña **Deploy & Run Transactions**:  
- En **Environment**, selecciona **Injected Provider - MetaMask**.  
- Elegí tu cuenta de MetaMask conectada a Sepolia.  
- En el campo **argumento del constructor**, ingresa el límite global y el umbral de retiros del banco en **wei** (ej: `100000000000000000000` = 100 ETH).  
- Haz clic en **Deploy** y confirma la transacción en MetaMask.  

8. Una vez desplegado, el contrato aparecerá en la sección **Deployed Contracts**.  
Desde allí podés interactuar con todas sus funciones.  

---

### 🛠️ Ejemplos de uso  

- **Depositar ETH**  
- En `depositarEnBoveda()`, escribe el monto en el campo `Value` (ej: `1000000000000000000` = 1 ETH).  
- Haz clic en `transact` y confirma en MetaMask.  

- **Ver tu saldo**  
- Haz clic en `verBoveda()` y verás tu saldo en la bóveda.  

- **Retirar fondos**  
- Llama a `retirarDeBoveda(uint monto)` con el valor en wei (ej: `500000000000000000` = 0.5 ETH).  
- Confirma la transacción en MetaMask.  

---

## 🛡️ Protección Anti-Reentrancy: Tu Dinero Está Seguro

KipuBank implementa una **defensa de triple capa** contra ataques de reentrancy, uno de los vectores de ataque más peligrosos en smart contracts (responsable del hack de The DAO en 2016 que resultó en $60 millones de pérdidas):

**🔐 Sistema de Seguridad Multicapa:**
- **Patrón CEI** (Checks-Effects-Interactions): Actualizamos el estado antes de cualquier llamada externa
- **NonReentrant Guard**: Sistema de bloqueo que previene llamadas recursivas maliciosas  
- **Verificación de Call**: Validación automática del resultado con revert en caso de fallo
```solidity
modifier nonReentrant() {
    if(_status == _ENTERED) revert KipuBank_NonReentrant(msg.sender);
    _status = _ENTERED;
    _;
    _status = _NO_ENTERED;
}
```

---
### ⛓️ Dirección del contrato verificado

En el siguiente enlace vas a poder encontrar la dirección del contrato en el explorador de bloques:
<br>
   - https://sepolia.etherscan.io/address/0xF4f67F0C94b47E5679ec4Fa4AbD7b61fa39c0b80
# KipuBankV2
