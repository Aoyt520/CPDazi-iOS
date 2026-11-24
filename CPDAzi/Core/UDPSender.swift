import Foundation
import Network

/// UDP 7706 / 7707 / 7795 发送器 —— 对应 Android TcBridge.doSend()
final class UDPSender {
    private let queue = DispatchQueue(label: "z6.udp", qos: .userInitiated)
    private var connection: NWConnection?
    private var currentHost: String = ""
    private var currentPort: UInt16 = 0
    private(set) var lastSendAt = Date()

    func send(json: [String: Any], host: String, port: UInt16) {
        let data = FusionProtocol.jsonData(json)
        guard !data.isEmpty else { return }
        sendRaw(data, host: host, port: port)
    }

    func sendRaw(_ data: Data, host: String, port: UInt16) {
        queue.async { [weak self] in
            guard let self else { return }
            if self.connection == nil || self.currentHost != host || self.currentPort != port {
                self.connection?.cancel()
                let params = NWParameters.udp
                params.allowLocalEndpointReuse = true
                let c = NWConnection(host: NWEndpoint.Host(host),
                                     port: NWEndpoint.Port(rawValue: port) ?? 7706,
                                     using: params)
                c.start(queue: self.queue)
                self.connection = c
                self.currentHost = host
                self.currentPort = port
            }
            // 每个 Datagram 一次 send，与 Android 端新建 DatagramSocket 语义等价
            self.connection?.send(content: data, completion: .contentProcessed { _ in })
            self.lastSendAt = Date()
        }
    }

    func close() {
        queue.async { [weak self] in
            self?.connection?.cancel()
            self?.connection = nil
        }
    }
}
