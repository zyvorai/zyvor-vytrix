// SPDX-License-Identifier: BUSL-1.1
import Foundation
struct Snapshot: Codable, Equatable {
 struct Host: Codable, Equatable { var name:String; var os:String; var cores:Int; var memoryTotal:Double }
 struct AI: Codable, Equatable { var engine:String; var kind:String; var confidence:Int; var markers:[String] }
 struct Proc: Codable, Equatable, Identifiable { var pid:Int; var name:String; var app:String; var cpu:Double; var memory:Double; var project:String?; var ports:[Int]; var diskReadRate:Double?; var diskWriteRate:Double?; var networkInRate:Double?; var networkOutRate:Double?; var networkSockets:Int?; var ai:AI?; var id:Int{pid} }
 struct GPU: Codable, Equatable { var name:String; var backend:String?; var utilization:Double? }
 struct Accelerator: Codable, Equatable { var type:String; var name:String; var backend:String?; var available:Bool }
 struct ANE: Codable, Equatable { var available:Bool; var utilization:Double? }
 struct Metal: Codable, Equatable { var available:Bool }
 struct ThermalLimits: Codable, Equatable { var cpuSpeedLimit:Double?; var cpuSchedulerLimit:Double? }
 struct Hardware: Codable, Equatable { var chip:String?; var gpus:[GPU]?; var accelerators:[Accelerator]?; var metal:Metal?; var ane:ANE?; var temperatureCelsius:Double?; var powerWatts:Double?; var thermalLimits:ThermalLimits? }
 struct Inventory: Codable, Equatable { var agentVersion:String; var hostname:String; var architecture:String; var platform:String; var platformRelease:String; var python:String; var tools:[String:String]?; var macOS:String?; var model:String? }
 struct Agent: Codable, Equatable { var version:String; var uptimeSeconds:Double; var samples:Int; var failures:Int; var healthy:Bool }
 var version:Int;var timestamp:String;var host:Host;var cpu:Double;var memoryUsed:Double;var diskUsed:Double;var diskTotal:Double;var download:Double;var upload:Double;var battery:Double?;var processes:[Proc];var containers:[Container]?;var runtimes:[RuntimeStatus]?;var hardware:Hardware?;var inventory:Inventory?;var agent:Agent?
}
struct PortMapping:Codable,Hashable{var hostPort:Int?;var containerPort:Int;var `protocol`:String;var label:String{hostPort.map{"\($0)→\(containerPort)/\(`protocol`)"} ?? "\(containerPort)/\(`protocol`)"}}
struct Container:Codable,Equatable,Identifiable{var runtime:String;var id:String;var name:String;var image:String;var state:String;var cpu:Double;var memory:Double;var memoryLimit:Double?;var netIn:Double;var netOut:Double;var ports:[PortMapping];var isRunning:Bool{state.lowercased()=="running"}}
struct RuntimeStatus:Codable,Equatable{var name:String;var available:Bool;var error:String?}
struct HistoryResponse:Codable{var version:Int;var samples:[Snapshot]}
struct Sample:Identifiable,Equatable{var date:Date;var cpu:Double;var memory:Double;var disk:Double;var network:Double;var id:Date{date};init(_ s:Snapshot,at date:Date){self.date=date;cpu=s.cpu;memory=s.host.memoryTotal>0 ? s.memoryUsed/s.host.memoryTotal*100:0;disk=s.diskTotal>0 ? s.diskUsed/s.diskTotal*100:0;network=s.download+s.upload}}
struct AppGroup:Identifiable,Equatable{var name:String;var cpu:Double;var memory:Double;var processes:[Snapshot.Proc];var ports:[Int];var project:String?;var id:String{name};var processCount:Int{processes.count};var portsText:String{ports.map(String.init).joined(separator:", ")};static func group(_ s:Snapshot)->[AppGroup]{var groups:[String:AppGroup]=[:];for p in s.processes{var g=groups[p.app] ?? AppGroup(name:p.app,cpu:0,memory:0,processes:[],ports:[],project:p.project);g.cpu+=p.cpu;g.memory+=p.memory;g.processes.append(p);g.ports=Array(Set(g.ports+p.ports)).sorted();if g.project==nil{g.project=p.project};groups[p.app]=g};return groups.values.sorted{$0.cpu>$1.cpu}}}
enum Format{static func bytes(_ v:Double)->String{if v<1{return"0 B"};return ByteCountFormatter.string(fromByteCount:Int64(max(0,v)),countStyle:.binary)};static func rate(_ v:Double)->String{bytes(v)+"/s"};static func percent(_ v:Double)->String{String(format:"%.1f%%",v)}}
