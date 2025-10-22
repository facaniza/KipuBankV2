// SPDX-License-Identifier: MIT

pragma solidity ^0.8.30;

    /// @title KipuBank - Un banco en blockchain
    /// @author Facundo Alejandro Caniza

/// @notice Importaciones de OpenZeppelin
/// @dev Se debe importar las librerias/contratos ReentrancyGuard, IERC20, SafeIERC y Ownable
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/// @notice Importación de interfaz de Chainlink
/// @dev Usamos la importación de Data Feeds
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

contract KipuBank is ReentrancyGuard, Ownable {

    /// @dev Se amplia funcionalidad segura al IERC20
    using SafeERC20 for IERC20;

    /// @notice Direccion del Token ERC20
    /// @dev Es especifico para el token USDC
    IERC20 immutable i_usdc;

    /// @notice Interfaz publica del data feed
    /// @dev Utilizamos el data feed de Chainlink
    AggregatorV3Interface public i_feed;

    /// @notice Constante de refresco del precio del data feed
    /// @dev Por convención se establece en 3600
    uint16 constant HEARTBEAT = 3600;

    /// @notice Constante de decimales de conversión
    /// @dev Se hace la suma de los decimales de ethereum y de los decimales de la conversión de chainlink para restarles los decimales de USDC, nos da la base igualitaria
    uint constant DECIMAL_FACTOR = 1 * 10 ** 20;

    /// @notice Umbral para fijo para transaccion
    uint immutable i_umbral;

    /// @notice Limite global de deposito
    /// @dev Tener en cuenta que el limite global será en USD
    uint immutable i_bankCap;

    /// @notice Cantidad de depositos del contrato
    uint private _depositos = 0;

    /// @notice Cantidad de retiros del contrato
    uint private _retiros = 0;

    /// @notice Total de ether depositado en el contrato
    /// @dev El total del contrato es en USD
    uint private _totalContrato = 0;

    /// @notice Estructura que almacena por titular el monto que posee en los diferentes tokens
    mapping (address token => mapping (address titular => uint monto)) private _cuentasMultiToken;

    /// @notice Estructura que almacena el total de la boveda del titular
    /// @dev El total se calcula en USD
    mapping (address titular => uint monto) private _boveda;


    /// @notice Evento para depositos realizado exitosamente
    /// @param titular titular que realiza el detposito
    /// @param monto monto que se desea depositar
    event KipuBank_DepositoRealizado(address titular, uint monto);

    /// @notice Evento para extracciones realizadas exitosamente
    /// @param titular titular que desea realizar la extracción
    /// @param monto monto que se desea extraer
    event KipuBank_ExtraccionRealizada(address titular, uint monto);



    /// @notice Error de extraccion
    /// @param titular titular de la cuenta a realizar la extracción
    /// @param monto monto a extraer de la boveda
    error KipuBank_ExtraccionRechazada(address titular, uint monto);

    /// @notice Error por sobrepasarse del limite
    /// @param monto monto que excede el limite a depositar
    error KipuBank_LimiteExcedido(uint monto);

    /// @notice Error por saldo insuficiente
    /// @param titular titular con saldo insuficiente
    /// @param monto monto a retirar
    error KipuBank_SaldoInsuficiente(address titular, uint monto);

    /// @notice Error por umbral excedido
    /// @param monto que excede el umbral establecido
    error KipuBank_UmbralExcedido(uint monto);

    /// @notice Error monto cero
    /// @param titular titular que emite una transaccion con valor nulo
    error KipuBank_MontoCero(address titular);

    /// @notice Error por umbral invalido
    /// @param umbral umbral que es invalido
    error KipuBank_UmbralInvalido(uint umbral);

    /// @notice Error por limite invalido
    /// @param limite limite que es invalido
    error KipuBank_LimiteInvalido(uint limite);

    /// @notice Error de umbral mayor al limite
    /// @param umbral umbral del contrato
    /// @param limite limite del contrato
    error KipuBank_InicializacionInvalida(uint limite, uint umbral);

    /// @notice Error por operacion no permitida
    /// @param titular titular que realizo la operacion no permitida
    error KipuBank_OperacionNoPermitida(address titular);

    /// @notice Error por óraculo dando un precio equivoco
    /// @param precio Precio que dió el óraculo
    error KipuBank_OraculoComprometido(uint precio);

    /// @notice Error por precio desactualizado
    /// @param precio Es el precio que quedó desactualizado
    error KipuBank_PrecioDesactualizado(uint precio);

    /// @notice Constructor del contrato
    /// @param _limite Limite global que se permite por transaccion
    /// @param _umbral Umbral de limite de retiros
    /// @param _feed Direccion del data feed a utlizar
    /// @param _tokenERC20 Direccion del token ERC20 a utilizar
    /// @dev Se deben generar el limite, umbral y las direcciones del data feed y el token a utilizar al momento de desplegar el contrato
    constructor(uint _limite, uint _umbral, address _owner, address _feed, address _tokenERC20) Ownable(_owner) {
        if(_limite == 0) revert KipuBank_LimiteInvalido(_limite);
        if(_umbral == 0) revert KipuBank_UmbralInvalido(_umbral);
        if(_umbral > _limite) revert KipuBank_InicializacionInvalida(_limite, _umbral);
        if(_feed == address(0)) revert(); // error direccion de feeder invalida
        if(_tokenERC20 == address(0)) revert(); // error direccion de token invalida
        i_usdc = IERC20(_tokenERC20);
        i_feed = AggregatorV3Interface(_feed);
        i_bankCap = _limite;
        i_umbral = _umbral;
    }

    /// @notice Funcion receive() no permitida
    /// @dev El contrato no puede recibir ether sin data
    receive() external payable { revert KipuBank_OperacionNoPermitida(msg.sender); }

    /// @notice Funcion fallback() no permitida
    /// @dev El contrato no puede enviar data de manera no autorizada
    fallback() external payable { revert KipuBank_OperacionNoPermitida(msg.sender); }

    /// @notice Función para realizar la consulta del precio mediante óraculo
    /// @return precioUSD_ Retorna el precio en USD
    /// @dev Usamos el óraculo de ChainLink
    function chainLinkFeeds() internal view returns(uint precioUSD_) {
        (, int256 ethUSDPrice,, uint256 updateAt,) = i_feed.latestRoundData();
        if( ethUSDPrice == 0) revert KipuBank_OraculoComprometido(uint(ethUSDPrice));
        if(block.timestamp - updateAt > HEARTBEAT) revert KipuBank_PrecioDesactualizado(uint(ethUSDPrice));

        precioUSD_ = uint(ethUSDPrice);
    }

    /// @notice Modificador para verificar los depositos
    /// @param _monto es el monto a verificar
    modifier verificarDepositoETH(uint _monto) {
        uint montoUSDC = convertirEthEnUSDC(_monto);
        if(montoUSDC == 0) revert KipuBank_MontoCero(msg.sender);
        if (montoUSDC + _totalContrato > i_bankCap) revert KipuBank_LimiteExcedido(montoUSDC);
        _;
    }

    /// @notice Modificador para verificar los depositos
    /// @param _monto es el monto a verificar
    modifier verificarDepositoUSDC(uint _monto) {
        if(_monto == 0) revert KipuBank_MontoCero(msg.sender);
        if (_monto + _totalContrato > i_bankCap) revert KipuBank_LimiteExcedido(_monto);
        _;
    }    

    /// @notice Modificador para verificar los retiros
    /// @param _monto monto a verificar para el retiro
    /// @dev El umbral solo se aplica a los retiros de boveda
    modifier verificarRetiroETH(uint _monto) {
        uint montoUSDC = convertirEthEnUSDC(_monto);
        if(montoUSDC == 0) revert KipuBank_MontoCero(msg.sender);
        if (montoUSDC > i_umbral) revert KipuBank_UmbralExcedido(montoUSDC);
        if (_monto > _cuentasMultiToken[address(0)][msg.sender]) revert KipuBank_SaldoInsuficiente(msg.sender, montoUSDC);
        _;
    }

    /// @notice Modificador para verificar los retiros
    /// @param _monto monto a verificar para el retiro
    /// @dev El umbral solo se aplica a los retiros de boveda
    modifier verificarRetiroUSDC(uint _monto) {
        if(_monto == 0) revert KipuBank_MontoCero(msg.sender);
        if (_monto > i_umbral) revert KipuBank_UmbralExcedido(_monto);
        if (_monto > _cuentasMultiToken[address(i_usdc)][msg.sender]) revert KipuBank_SaldoInsuficiente(msg.sender, _monto);
        _;
    }    

    /// @notice Funcion privada para realizar el retiro efectivo de fondos en ETH
    /// @param _monto recibe el monto a retirar de la boveda
    /// @dev Se actualiza el estado antes de la transferencia para aplicar el patrón CEI
    /// @dev Se utiliza la funcion de OpenZeppelin para el nonReentrant
    function _retirarFondosETH(uint _monto) private nonReentrant verificarRetiroETH(_monto) {
        uint montoUSDC = convertirEthEnUSDC(_monto);
        _boveda[msg.sender] -= montoUSDC;
        _cuentasMultiToken[address(0)][msg.sender] -= _monto;
        _retiros++;
        _totalContrato -= montoUSDC;
        
        emit KipuBank_ExtraccionRealizada(msg.sender, montoUSDC);

        (bool success, ) = payable(msg.sender).call{value: _monto}("");
        if (!success) revert KipuBank_ExtraccionRechazada(msg.sender, _monto);
    }

    /// @notice Funcion privada para realizar el retiro efectivo de fondos en USDC
    /// @param _monto recibe el monto a retirar de la boveda
    /// @dev Se actualiza el estado antes de la transferencia para aplicar el patrón CEI
    /// @dev Se utiliza la funcion de OpenZeppelin para el nonReentrant
    /// @dev Se utiliza la interfaz SafeIERC20 para realizar la transferencia de token ERC20
    function _retirarFondosUSDC(uint _monto) private nonReentrant verificarRetiroUSDC(_monto) {
        _boveda[msg.sender] -= _monto;
        _cuentasMultiToken[address(i_usdc)][msg.sender] -= _monto;
        _retiros++;
        _totalContrato -= _monto;
        
        emit KipuBank_ExtraccionRealizada(msg.sender, _monto);
        i_usdc.safeTransfer(msg.sender, _monto);
    }

    /// @notice Funcion externa para realizar el retiro de saldo en ETH
    /// @param _monto es el monto a retirar de la boveda
    function retirarETH(uint _monto) external  {
        _retirarFondosETH(_monto);
    }

    /// @notice Funcion externa para realizar el retiro de saldo en USDC
    /// @param _monto es el monto a retirar de la boveda
    function retirarUSDC(uint _monto) external {
        _retirarFondosUSDC(_monto);
    }    

    /// @notice Funcion para depositar en la boveda
    /// @dev Es payable y usa el modificador de verificarDepositos
    function depositarETH() external payable verificarDepositoETH(msg.value) {
        uint montoUSDC = convertirEthEnUSDC(msg.value);
        _cuentasMultiToken[address(0)][msg.sender] += msg.value;
        _boveda[msg.sender] += montoUSDC;
        _depositos++;
        _totalContrato += montoUSDC;
        emit KipuBank_DepositoRealizado(msg.sender, montoUSDC);
    }

    /// @notice Funcion para depositar en la boveda
    /// @dev Es payable y usa el modificador de verificarDepositos
    /// @dev Se utiliza la interfaz SafeIERC20 para realizar la transferencia de token ERC20
    /// @dev No se marca como payable ya que es un token ERC20 y no Ether
    function depositarUSDC(uint _monto) external verificarDepositoUSDC(_monto) {
        _cuentasMultiToken[address(i_usdc)][msg.sender] += _monto;
        _boveda[msg.sender] += _monto;
        _depositos++;
        _totalContrato += _monto;
        emit KipuBank_DepositoRealizado(msg.sender, _monto);
        i_usdc.safeTransferFrom(msg.sender, address(this), _monto);
    }
    
    /// @notice Funcion para convertir ETH en USDC
    /// @param _monto Es el monto ingresado a convertir
    /// @return montoConvertido_ Es el monto una vez convertido a USD
    /// @dev La cuenta debe hacerse debido a que los decimales de USDC y ETH no son los mismos, por lo tanto, se nivelan las bases
    function convertirEthEnUSDC(uint _monto) internal view returns (uint montoConvertido_) {
            montoConvertido_ = (_monto * chainLinkFeeds()) / DECIMAL_FACTOR;
    }

    /// @notice Funcion para ver el saldo total guardado en el boveda en USD
    /// @return monto_ devuelve el saldo depositado total en USD depositado por cada titular
    function verBoveda() external view returns (uint monto_) {
        monto_ = _boveda[msg.sender];
    }

    /// @notice Función para ver el saldo en USDC del titular
    /// @return saldo_ Retorna el saldo en USDC
    function verSaldoUSDC() external view returns (uint saldo_) {
        saldo_ = _cuentasMultiToken[address(i_usdc)][msg.sender];
    }

    /// @notice Función para el saldo en ETH del titular
    /// @return saldo_ Retornal el saldo en ETH
    function verSaldoETH() external view returns (uint saldo_) {
        saldo_ = _cuentasMultiToken[address(0)][msg.sender];
    }

    /// @notice Funcion para ver la cantidad total de los depositos realizados
    /// @return Devuelve la cantidad de depositos
    function verTotalDepositos() external view returns (uint) {
        return _depositos;
    }

    /// @notice Funcion para ver la cantidad total de los retiros realizados
    /// @return Devuelve la cantidad de retiros
    function verTotalRetiros() external view returns (uint) {
        return _retiros;
    }

    /// @notice Funcion para ver el saldo total del contrato en USD
    /// @return Devuelve el saldo del contrato en USD
    function verTotalContrato() external view returns (uint) {
        return _totalContrato;
    }

    /// @notice Función para traspasar el contrato a otro dueño
    /// @param _nuevoOwner Será la dirección del nuevo propietario del contrato
    /// @dev El modificador de onlyOwner es necesario para seguridad
    function transferirOwner(address _nuevoOwner) external onlyOwner {
        transferOwnership(_nuevoOwner);
    }

}