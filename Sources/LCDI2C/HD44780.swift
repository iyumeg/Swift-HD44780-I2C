import Foundation
import I2C

internal let bitLCDClear    : UInt8 = 0
internal let bitLCDReset    : UInt8 = 1
internal let bitLCDSetMode  : UInt8 = 2
internal let bitFlagI_D     : UInt8 = 1   // [I/D] 1 - Inc, 0 - Dec
internal let bitFlagS       : UInt8 = 0   // [S] 1 - Shift display, 0 - No shift
internal let bitLCDSetting  : UInt8 = 3
internal let bitFlagD       : UInt8 = 2   // [D] 1 - On, 0 - Off
internal let bitFlagC       : UInt8 = 1   // [C] 1 - Underline cursor
internal let bitFlagB       : UInt8 = 0   // [B] 1 - Blink cursor
internal let bitLCDSetShift : UInt8 = 4
internal let bitFlagS_C     : UInt8 = 3   // [S/C] 1 - Screen, 0 - Cursor
internal let bitFlagR_L     : UInt8 = 2   // [R/L] 1 - Right, 0 - Left
internal let bitLCDConfig   : UInt8 = 5
internal let bitFlagDL      : UInt8 = 4   // [DL] 1 - 8bit, 0 - 4bit
internal let bitFlagN       : UInt8 = 3   // [N] 0 - single line mode
internal let bitFlagF       : UInt8 = 2   // [F] 1 - 5x11, 0 - 5x8
internal let bitAddressCGRAM: UInt8 = 6
internal let bitAddressDDRAM: UInt8 = 7



public class LCD{
    public enum Polarity: UInt8 {
        case Negative
        case Positive
    }

    public enum CommandType: UInt8 {
        case Instruction
        case Data
    }

    public enum Action: UInt8 {
        case Write
        case Read
    }

    public enum RamType: UInt8 {
        case CGRAM
        case DDRAM
    }

    // I2C Bus Device
    private var device: I2CBusDevice

    // Config Properties
    private let rs,rw,bl,e,address: UInt8
    public let width: UInt8
    public let height: UInt8
    public let polarity: Polarity

    // Supporting Properties
    private var temp = [String:UInt8]()       // Temp data

    public var clockData: UInt8{
        var backlightBit = temp["bl"] ?? 1
        if polarity == .Negative{
            backlightBit = ~backlightBit & 1
        }
        return backlightBit << bl
    }

    init(address: UInt8, width: UInt8, height: UInt8, rs: UInt8 = 0, rw: UInt8  = 1, e: UInt8 = 2, bl: UInt8 = 3, polarity: Polarity = .Positive) throws {
        self.address    = address
        self.width      = width
        self.height     = height
        self.rs         = rs
        self.rw         = rw
        self.bl         = bl
        self.e          = e
        self.polarity   = polarity
        self.temp["bl"] = 1
        self.device     = try I2CBusDevice(portNumber: 1)
        initDisplay()
    }

    private func initDisplay(){
        usleep(15000)
        transmission(data: [0b00111100])
        usleep(4100)
        transmission(data: [0b00111100])
        usleep(100)
        transmission(data: [0b00111100])
        usleep(500)
        transmission(data: [0b00101100])
        configDisplay(show: true, enableCursor: false, blinkCursor: false)
        setShift(screen: false, right: true)
        clearScreen()
        resetScreen()
    }


    ///
    /// Clears entire display and sets DDRAM address 0 in address counter.
    ///
    public func clearScreen(){
        sendData(act: .Write, type: .Instruction, data: [1 << bitLCDClear])
        temp["AC"] = 0
    }

    ///
    /// Sets DDRAM address 0 in address counter.
    /// Also returns display from being shifted to origina position.
    /// DDRAM contents remain unchanged.
    ///
    public func resetScreen(){
        sendData(act: .Write, type: .Instruction, data: [1 << bitLCDReset])
        temp["AC"] = 0
        usleep(152000)
    }

    ///
    /// Sets cursor move direction and specifies display shift.
    /// These operations are performed during data write and read.
    ///
    /// - parameter increment: T - Increment, F - Decrement
    /// - parameter shift: T- Shift screen, F - No Shift
    ///
    public func setEntryMode(increment: Bool, shift: Bool){
        var data = 1 << bitLCDSetMode
        data |= (increment ? 1 : 0) << bitFlagI_D
        data |= (shift ? 1: 0) << bitFlagS
        sendData(act: .Write, type: .Instruction, data: [data])

        temp["incremenet"] = increment ? 1 : 0
        temp["shift"] = shift ? 1: 0
        usleep(37)
    }

    ///
    /// Sets entire display (status) on/off,
    /// cursor on/off (cursor),
    /// and blinking of cursor position character (blink).
    ///
    /// - parameter show: Display Status T - On, F - Off
    /// - parameter cursor: Cursor T - On, F - Off
    /// - parameter blink: Cursor Blink T- On, F - Off
    ///
    public func configDisplay(show: Bool, enableCursor: Bool, blinkCursor: Bool){
        var data = 1 << bitLCDSetting
        data |= (show ? 1 : 0) << bitFlagD
        data |= (enableCursor ? 1 : 0) << bitFlagC
        data |= (blinkCursor ? 1 : 0) << bitFlagB
        sendData(act: .Write, type: .Instruction, data: [data])

        temp["show"] = show ? 1 : 0
        temp["enableCursor"] = enableCursor ? 1 : 0
        temp["blinkCursor"] = blinkCursor ? 1 : 0
        usleep(37)
    }

    ///
    /// Moves cursor and shifts display without changing DDRAM contents
    ///
    /// - parameter screen: Object for shift T - Screen, F - Cursor
    /// - parameter right: Shift direction T - Right, F - Left
    ///
    public func setShift(screen: Bool, right: Bool){
        var data = 1 << bitLCDSetShift
        data |= (screen ? 1 : 0 )  << bitFlagS_C
        data |= (right ? 1 : 0) << bitFlagR_L
        sendData(act: .Write, type: .Instruction, data: [data])
        usleep(37)
    }

    ///
    /// Sets interface data length (DL), number of display lines (N), and character font (F).
    ///
    /// - parameter interface: Data length T - 8 Bit, F - 4 Bit
    /// - parameter singeLine: Single line mode
    /// - parameter charSize: Character size T - 5x10 dots, F = 5x8 dots
    ///
    public func setFunction(longData: Bool, singleLine: Bool, bigChars: Bool){
        var data = 1 << bitLCDConfig
        data |= (longData ? 1 : 0) << bitFlagDL
        data |= (singleLine ? 1 : 0) << bitFlagN
        data |= (bigChars ? 1 : 0) << bitFlagF
        sendData(act: .Write, type: .Instruction, data: [data])

        temp["longData"] = longData ? 1 : 0
        temp["singleLine"] = singleLine ? 1 : 0
        temp["bigChars"] = bigChars ? 1 : 0
        usleep(37)
    }

    ///
    /// Set CGRAM/DDRAM address
    ///
    /// - parameter type: Ram type (CGRAM or DDRAM)
    /// - parameter address: Address (6 or 7 bit)
    ///
    public func setAddress(type: RamType, address: UInt8){
        var data = address
        switch type {
        case .CGRAM:
            data |= 1 << bitAddressCGRAM
            data &= 0b01111111
        case .DDRAM:
            data |= 1 << bitAddressDDRAM
        }
        sendData(act: .Write, type: .Instruction, data: [data])
        temp["AC"] = address
        usleep(37)
    }

    ///
    /// Set cursor position
    ///
    /// - parameter x: Number of column. [0 first]
    /// - parameter y: Number of row. [0 first]
    ///
    public func cursor(x: UInt8, y: UInt8){
        guard x < width && y < height else {return}
        let address = 0x40 * y + x
        setAddress(type: .DDRAM, address: address)
    }

    ///
    /// Print string on the screen
    ///
    /// - parameter string: String to print
    ///
    public func print(_ string: String){
        let validChars = string.unicodeScalars.filter{$0.isASCII}.map{UInt8($0.value)}
        sendData(act: .Write, type: .Data, data: validChars)
    }

    ///
    /// Print string on the screen in XY position
    ///
    /// - parameter string: String to print
    /// - parameter x: Horizontal position (starting from 0)
    /// - parameter y: Vertical position (starting from 0)
    ///
    public func printAt(_ string: String, x: UInt8, y: UInt8){
        cursor(x: x, y: y)
        print(string)
    }

    public func printCustomAt(_ charAddress: UInt8, x: UInt8, y: UInt8){
        guard 0...7 ~= charAddress else {return}
        cursor(x: x, y: y)
        sendData(act: .Write, type: .Data, data: [charAddress])
    }

    public func draw(_ customChar: [UInt8], at: UInt8){
        guard customChar.count == 8 else {return}
        guard 0...7 ~= at else {return}
        let lastAddress = temp["AC"] ?? 0
        setAddress(type: .CGRAM, address: at << 3)
        sendData(act: .Write, type: .Data, data: customChar)
        setAddress(type: .DDRAM, address: lastAddress)
    }
    
    public func draw(_ customByte: UInt8, at: UInt8){
        let lastAddress = temp["AC"] ?? 0
        setAddress(type: .CGRAM, address: at)
        sendData(act: .Write, type: .Data, data: [customByte])
        setAddress(type: .DDRAM, address: lastAddress)        
    }

    private func sendData(act: Action, type: CommandType, data: [UInt8]){
        let nibbles = data.flatMap{[$0 & 0b11110000, $0 << 4]}
        var readyBytes = [UInt8]()
        for nibble in nibbles{
            var sendData = nibble
            sendData |= type.rawValue << rs
            sendData |= act.rawValue << rw
            sendData |= 1 << e
            sendData |= polarity.rawValue << bl
            readyBytes.append(sendData)
        }
        transmission(data: readyBytes)
    }


    private func transmission(data: [UInt8]){
        do{
            _ = try device.write(toAddress: address, data: data.flatMap{[$0,clockData]}, readBytes: 1)
        }catch{
            // TODO: print error, or maybe break/exit
        }
    }
}
