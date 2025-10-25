// SPDX-License-Identifier: MIT

pragma solidity ^0.8.30;

    /// @title KipuBank - Un banco en blockchain
    /// @author Facundo Alejandro Caniza

/// @notice Importaciones de OpenZeppelin
/// @dev Se debe importar las librerias/contratos ReentrancyGuard, IERC20, SafeIERC, Ownable, Pausable y AccesControl
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

/// @notice Importación de interfaz de Chainlink
/// @dev Usamos la importación de Data Feeds
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

contract KipuBank is ReentrancyGuard, Ownable, Pausable, AccessControl {

    /// @notice Rol de pausador del contrato
    bytes32 public constant PAUSER = keccak256("PAUSER");

    /// @notice Rol de Manager de los data feeds
    bytes32 public constant FEED_MANAGER = keccak256("FEED_MANAGER");

    /// @notice Interfaz publica del data feed
    /// @dev Utilizamos el data feed de Chainlink
    AggregatorV3Interface public s_feed;

    /// @notice Direccion del Token ERC20
    /// @dev Es especifico para el token USDC
    IERC20 immutable i_usdc;    

    /// @notice Se usa la interfaz SafeERC20 para ampliar una funcionalidad segura en IERC20
    /// @dev Se amplia funcionalidad segura al IERC20
    using SafeERC20 for IERC20;

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

    /// @notice Total de ether depositado en el contrato
    /// @dev El total del contrato es en USD
    uint private s_totalContrato = 0;

    /// @notice Deposito mínimo de Ether en el contrato
    uint public constant MIN_DEPOSITO = 1 gwei;

    /// @notice Cantidad de depositos del contrato
    uint128 private s_depositos = 0;

    /// @notice Cantidad de retiros del contrato
    uint128 private s_retiros = 0;    

    /// @notice Estructura que almacena por titular el monto que posee en los diferentes tokens
    /// @dev En el primer mapping tenemos la direcciones del token, en el segundo mapping tenemos las direcciones de los titulares
    mapping (address token => mapping (address titular => uint monto)) private s_cuentasMultiToken;

    /// @notice Evento para depositos realizado exitosamente
    /// @param titular titular que realiza el detposito
    /// @param monto monto que se desea depositar
    event KipuBank_DepositoRealizado(address indexed titular, uint monto);

    /// @notice Evento para extracciones realizadas exitosamente
    /// @param titular titular que desea realizar la extracción
    /// @param monto monto que se desea extraer
    event KipuBank_ExtraccionRealizada(address indexed titular, uint monto);

    /// @notice Evento para la actualización del feed
    /// @param antiguoFeed Es el antiguo data feed utilizado
    /// @param nuevoFeed Es el nuevo data feed a ser utilizado
    event KipuBank_FeedActualizado(address indexed antiguoFeed, address indexed nuevoFeed);

    /// @notice Evento para pausar el contrato
    /// @param sender Es la dirección que pauso el contrato
    /// @param tiempo Es el tiempo en el que fue pausado el contrato
    event KipuBank_ContratoPausado(address indexed sender, uint tiempo);

    /// @notice Evento para despausar el contrato
    /// @param sender Es la direccion que despausó el contrato
    /// @param tiempo Es el tiempo en el que fue despausado
    event KipuBank_ContratoDespausado(address indexed sender, uint tiempo);

    /// @notice Evento para cuando el owner del contrato es transferido
    /// @param ownerViejo Es el anterior owner del contrato
    /// @param ownerNuevo Es el nuevo owner del contrato
    event KipuBank_OwnerTransferido( address indexed ownerViejo, address indexed ownerNuevo);

    /// @notice Evento para cuando un rol es otorgado
    /// @param cuenta Es la cuenta que recibe el nuevo rol
    /// @param rol Es el rol que se le asigna a la cuenta
    event KipuBank_RolDado(address indexed cuenta, bytes32 rol);

    /// @notice Evento para cuando un rol es revocado
    /// @param cuenta Es la cuenta a la que se revoca el rol
    /// @param rol Es el rol que se elimina de la cuenta
    event KipuBank_RolRevocado(address indexed cuenta, bytes32 rol);

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

    /// @notice Error por querer hacer un "set" de una dirección invalida
    error KipuBank_DireccionInvalida();

    /// @notice Error por querer ingresar un data feed invalido
    /// @param nuevoFeed Es el data feed erroneo que quiso ser ingresado
    error KipuBank_FeedInvalido(address nuevoFeed);

    /// @notice Error cuando alguien no autorizado quiere acceder a una función
    /// @param sender Es la cuenta que quiso acceder a la función
    error KipuBank_NoAutorizado(address sender);

    /// @notice Error de monto no autorizado a depositar
    /// @param monto Monto excedido
    error KipuBank_MontoNoAutorizado(uint monto);

    error KipuBank_InferiorDepositoMinimo(uint monto);

    /// @notice Constructor del contrato
    /// @param _limite Limite global que se permite por transaccion
    /// @param _umbral Umbral de limite de retiros
    /// @param _feed Direccion del data feed a utlizar
    /// @param _tokenERC20 Direccion del token ERC20 a utilizar
    /// @dev Se deben generar el limite, umbral y las direcciones del data feed y el token a utilizar al momento de desplegar el contrato
    constructor(
        uint _limite, 
        uint _umbral, 
        address _owner, 
        address _feed, 
        address _tokenERC20) 
        Ownable(_owner) {
        if(_limite == 0) revert KipuBank_LimiteInvalido(_limite);
        if(_umbral == 0) revert KipuBank_UmbralInvalido(_umbral);
        if(_umbral > _limite) revert KipuBank_InicializacionInvalida(_limite, _umbral);
        if(_feed == address(0)) revert KipuBank_DireccionInvalida();
        if(_tokenERC20 == address(0)) revert KipuBank_DireccionInvalida();
        
        _grantRole(DEFAULT_ADMIN_ROLE, _owner);
        _grantRole(PAUSER, _owner);
        _grantRole(FEED_MANAGER, _owner);

        i_usdc = IERC20(_tokenERC20);
        s_feed = AggregatorV3Interface(_feed);
        i_bankCap = _limite;
        i_umbral = _umbral;
    }

    /// @notice Funcion receive() no permitida
    /// @dev El contrato no puede recibir ether sin data
    receive() external payable { revert KipuBank_OperacionNoPermitida(msg.sender); }

    /// @notice Funcion fallback() no permitida
    /// @dev El contrato no puede enviar data de manera no autorizada
    fallback() external payable { revert KipuBank_OperacionNoPermitida(msg.sender); }

    /// @notice Modificador para que administrar el acceso a la funciones, solo por Rol o por Owner
    /// @param rol Es el rol que tiene permise a acceder a la función
    modifier soloOwnerORol(bytes32 rol) {
        if(owner() != msg.sender && !hasRole(rol, msg.sender)) {
            revert KipuBank_NoAutorizado(msg.sender);
        }
        _;
    }    

    /// @notice Modificador para verificar los depositos
    /// @param _montoUSD es el monto a verificar
    modifier verificarDepositoETH(uint _montoUSD, uint _montoETH) {
        if(_montoETH < MIN_DEPOSITO) revert KipuBank_InferiorDepositoMinimo(_montoETH);
        if(_montoUSD == 0) revert KipuBank_MontoCero(msg.sender);
        if(_montoUSD + s_totalContrato > i_bankCap) revert KipuBank_LimiteExcedido(_montoUSD);
        _;
    }

    /// @notice Modificador para verificar los depositos
    /// @param _monto es el monto a verificar
    modifier verificarDepositoUSDC(uint _monto) {
        if(_monto == 0) revert KipuBank_MontoCero(msg.sender);
        if (_monto + s_totalContrato > i_bankCap) revert KipuBank_LimiteExcedido(_monto);
        _;
    }    

    /// @notice Modificador para verificar los retiros
    /// @param _monto monto a verificar para el retiro
    /// @dev El umbral solo se aplica a los retiros de boveda
    modifier verificarRetiroETH(uint _monto) {
        uint montoUSDC = convertirEthEnUSD(_monto);
        if(montoUSDC == 0) revert KipuBank_MontoCero(msg.sender);
        if (montoUSDC > i_umbral) revert KipuBank_UmbralExcedido(montoUSDC);
        if (_monto > s_cuentasMultiToken[address(0)][msg.sender]) revert KipuBank_SaldoInsuficiente(msg.sender, montoUSDC);
        _;
    }

    /// @notice Modificador para verificar los retiros
    /// @param _monto monto a verificar para el retiro
    /// @dev El umbral solo se aplica a los retiros de boveda
    modifier verificarRetiroUSDC(uint _monto) {
        if(_monto == 0) revert KipuBank_MontoCero(msg.sender);
        if (_monto > i_umbral) revert KipuBank_UmbralExcedido(_monto);
        if (_monto > s_cuentasMultiToken[address(i_usdc)][msg.sender]) revert KipuBank_SaldoInsuficiente(msg.sender, _monto);
        _;
    }    

    /// @notice Función para realizar la consulta del precio mediante óraculo
    /// @return precioUSD_ Retorna el precio en USD
    /// @dev Usamos el óraculo de ChainLink
    function chainLinkFeeds() internal view returns(uint precioUSD_) {
        (, int256 ethUSDPrice,, uint256 updateAt,) = s_feed.latestRoundData();
        if( ethUSDPrice <= 0) revert KipuBank_OraculoComprometido(uint(ethUSDPrice));
        if(block.timestamp - updateAt > HEARTBEAT) revert KipuBank_PrecioDesactualizado(uint(ethUSDPrice));

        precioUSD_ = uint(ethUSDPrice);
    }

    /// @notice Funcion para convertir ETH en USDC
    /// @param _monto Es el monto ingresado a convertir
    /// @return montoConvertido_ Es el monto una vez convertido a USD
    /// @dev La cuenta debe hacerse debido a que los decimales de USDC y ETH no son los mismos, por lo tanto, se nivelan las bases
    function convertirEthEnUSD(uint _monto) internal view returns (uint montoConvertido_) {
            montoConvertido_ = (_monto * chainLinkFeeds()) / DECIMAL_FACTOR;
    }    

    /// @notice Funcion privada para realizar el retiro efectivo de fondos en ETH
    /// @param _monto recibe el monto a retirar de la boveda
    /// @dev Se actualiza el estado antes de la transferencia para aplicar el patrón CEI
    /// @dev Se utiliza la funcion de OpenZeppelin para el nonReentrant
    function _retirarFondosETH(uint _monto) private nonReentrant verificarRetiroETH(_monto) {
        uint montoUSD = convertirEthEnUSD(_monto);
        s_cuentasMultiToken[address(0)][msg.sender] -= _monto;
        s_retiros++;
        s_totalContrato -= montoUSD;
        
        emit KipuBank_ExtraccionRealizada(msg.sender, montoUSD);

        (bool success, ) = payable(msg.sender).call{value: _monto}("");
        if (!success) revert KipuBank_ExtraccionRechazada(msg.sender, _monto);
    }

    /// @notice Funcion privada para realizar el retiro efectivo de fondos en USDC
    /// @param _monto recibe el monto a retirar de la boveda
    /// @dev Se actualiza el estado antes de la transferencia para aplicar el patrón CEI
    /// @dev Se utiliza la funcion de OpenZeppelin para el nonReentrant
    /// @dev Se utiliza la interfaz SafeIERC20 para realizar la transferencia de token ERC20
    function _retirarFondosUSDC(uint _monto) private nonReentrant verificarRetiroUSDC(_monto) {
        s_cuentasMultiToken[address(i_usdc)][msg.sender] -= _monto;
        s_retiros++;
        s_totalContrato -= _monto;
        emit KipuBank_ExtraccionRealizada(msg.sender, _monto);
        i_usdc.safeTransfer(msg.sender, _monto);
    }

    /// @notice Funcion externa para realizar el retiro de saldo en ETH
    /// @param _monto es el monto a retirar de la boveda
    function retirarETH(uint _monto) external whenNotPaused {
        _retirarFondosETH(_monto);
    }

    /// @notice Funcion externa para realizar el retiro de saldo en USDC
    /// @param _monto es el monto a retirar de la boveda
    function retirarUSDC(uint _monto) external whenNotPaused {
        _retirarFondosUSDC(_monto);
    } 

    /// @notice Función privada para depositar ETH
    /// @dev Se hace una función auxiliar para ahorrar llamadas al data feed
    function _depositoETH(address titular, uint montoUSD, uint montoETH) private verificarDepositoETH(montoUSD, montoETH) {
        s_cuentasMultiToken[address(0)][titular] += montoETH;
        s_depositos++;
        s_totalContrato += montoUSD;
        emit KipuBank_DepositoRealizado(titular, montoUSD);
    }

    /// @notice Funcion para depositar en la boveda
    /// @dev Debe ser payable
    function depositarETH() external payable whenNotPaused {
        uint montoETH = msg.value;
        uint montoUSD = convertirEthEnUSD(montoETH);
        _depositoETH(msg.sender, montoUSD, montoETH);
    }

    /// @notice Funcion para depositar en la boveda
    /// @dev Es payable y usa el modificador de verificarDepositos
    /// @dev Se utiliza la interfaz SafeIERC20 para realizar la transferencia de token ERC20
    /// @dev No se marca como payable ya que es un token ERC20 y no Ether
    /// @dev Necesitamos la aprobación del dueño de los USDC para depositar
    function depositarUSDC(uint _monto) external verificarDepositoUSDC(_monto) whenNotPaused {
        if ( i_usdc.allowance(msg.sender, address(this)) < _monto ) revert KipuBank_MontoNoAutorizado(_monto);
        s_cuentasMultiToken[address(i_usdc)][msg.sender] += _monto;
        s_depositos++;
        s_totalContrato += _monto;
        emit KipuBank_DepositoRealizado(msg.sender, _monto);
        i_usdc.safeTransferFrom(msg.sender, address(this), _monto);
    }

    /// @notice Funcion para ver el saldo total guardado en el boveda en USD
    /// @return monto_ devuelve el saldo depositado total en USD depositado por cada titular
    function verBoveda() external view returns (uint monto_) {
        monto_ = convertirEthEnUSD(s_cuentasMultiToken[address(0)][msg.sender]) + s_cuentasMultiToken[address(i_usdc)][msg.sender];
    }

    /// @notice Función para ver el saldo en USDC del titular
    /// @return saldo_ Retorna el saldo en USDC
    function verSaldoUSDC() external view returns (uint saldo_) {
        saldo_ = s_cuentasMultiToken[address(i_usdc)][msg.sender];
    }

    /// @notice Función para el saldo en ETH del titular
    /// @return saldo_ Retornal el saldo en ETH
    function verSaldoETH() external view returns (uint saldo_) {
        saldo_ = s_cuentasMultiToken[address(0)][msg.sender];
    }

    /// @notice Funcion para ver la cantidad total de los depositos realizados
    /// @return Devuelve la cantidad de depositos
    function verTotalDepositos() external view returns (uint) {
        return s_depositos;
    }

    /// @notice Funcion para ver la cantidad total de los retiros realizados
    /// @return Devuelve la cantidad de retiros
    function verTotalRetiros() external view returns (uint) {
        return s_retiros;
    }

    /// @notice Funcion para ver el saldo total del contrato en USD
    /// @return Devuelve el saldo del contrato en USD
    function verTotalContrato() external view returns (uint) {
        return s_totalContrato;
    }

    /// @notice Función para traspasar el contrato a otro dueño
    /// @param _nuevoOwner Será la dirección del nuevo propietario del contrato
    /// @dev El modificador de onlyOwner es necesario para seguridad
    function transferirOwner(address _nuevoOwner) external onlyOwner whenPaused {
        
        address ownerActual = owner();

        _revokeRole(DEFAULT_ADMIN_ROLE, ownerActual);
        _revokeRole(PAUSER, ownerActual);
        _revokeRole(FEED_MANAGER, ownerActual);

        _transferOwnership(_nuevoOwner);

        _grantRole(DEFAULT_ADMIN_ROLE, _nuevoOwner);
        _grantRole(FEED_MANAGER, _nuevoOwner);
        _grantRole(PAUSER, _nuevoOwner);

        emit KipuBank_OwnerTransferido(ownerActual, _nuevoOwner);
    }

    /// @notice Función para cambiar el data feeds
    /// @param _nuevoFeed Será la dirección del nuevo data feed del contrato
    /// @dev Solo pueden acceder a ella el owner o los que tengan el rol FEED_MANAGER
    function setFeeds(address _nuevoFeed) external soloOwnerORol(FEED_MANAGER) whenPaused {
        if (_nuevoFeed == address(0)) revert KipuBank_DireccionInvalida();

        try AggregatorV3Interface(_nuevoFeed).latestRoundData() returns (
            uint80, int256 price, uint256, uint256 updateAt, uint80
        ) {
            if(price <= 0) revert KipuBank_FeedInvalido(_nuevoFeed);
           
            if(block.timestamp - updateAt > HEARTBEAT) revert KipuBank_PrecioDesactualizado(uint(price));
            
            address feedAnterior = address(s_feed);
            s_feed = AggregatorV3Interface(_nuevoFeed);
            emit KipuBank_FeedActualizado(feedAnterior, _nuevoFeed);
        } catch {
            revert KipuBank_FeedInvalido(_nuevoFeed);
        }        
    }

    /// @notice Función para pausar el contrato
    /// @dev Solo pueden acceder a ella el owner el aquellos que tengan rol PAUSER
    function pausarContrato() external soloOwnerORol(PAUSER) whenNotPaused {
        _pause();
        emit KipuBank_ContratoPausado(msg.sender, block.timestamp);
    }

    /// @notice Función para despausar el contrato
    /// @dev Solo pueden acceder a ella el owner el aquellos que tengan rol PAUSER
    function despausarContrato() external soloOwnerORol(PAUSER) whenPaused {
        _unpause();
        emit KipuBank_ContratoDespausado(msg.sender, block.timestamp);
    }

    /// @notice Función para dar un rol a una cuenta
    /// @param cuenta Es la cuenta que recibe el rol
    /// @param rol Es el rol dado a la cuenta
    function darRol(address cuenta, bytes32 rol) external onlyOwner {
        grantRole(rol, cuenta);
        emit KipuBank_RolDado(cuenta, rol);
    }

    /// @notice Función para revocar el rol a una cuenta
    /// @param cuenta Es la cuenta a la que se le revoca el rol
    /// @param rol Es el rol revocado de la cuenta
    function revocarRol(address cuenta, bytes32 rol) external onlyOwner {
        revokeRole(rol, cuenta);
        emit KipuBank_RolRevocado(cuenta, rol);
    }

    /// @notice Función para ver el estado del contrato
    function estadoDelContrato() external view 
    returns (
        bool pausado, 
        uint totalContrato, 
        uint limite, 
        uint umbral, 
        address feedActual
        ) {
        return (
            paused(),
            s_totalContrato,
            i_bankCap,
            i_umbral,
            address(s_feed)
        );
    }    

    /// @notice Función para ver el saldo por token del titular
    /// @param titular Es el titular de la cuenta
    /// @param token Es el token que se desea consultar
    /// @return Retorna un entero sin signo, que es el saldo correspondiente
    function balanceOf(address titular, address token) external view returns (uint) {
        return s_cuentasMultiToken[token][titular];
    }

    /// @notice Override requerido por Solidity para la múltiple herencia
    function supportsInterface(bytes4 interfaceId) 
        public 
        view 
        virtual 
        override(AccessControl) 
        returns (bool) 
    {
        return super.supportsInterface(interfaceId);
    }

}