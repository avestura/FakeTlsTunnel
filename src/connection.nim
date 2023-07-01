import overrides/[asyncnet]
import std/[tables,sequtils, times,os , random, asyncdispatch,strformat, strutils, net, random]
import globals

type
    TrustStatus*{.pure.} = enum
        no, pending, yes

    Connection* = ref object
        creation_time*: uint        #creation epochtime
        action_start_time*: uint    #when recv/send action started (0 = idle)
        register_start_time*: uint  #when the connection is added to the pool (0 = idle)
        id*: uint32                 #global incremental id
        trusted*: TrustStatus       #when fake handshake perfromed
        socket*: AsyncSocket        #wrapped asyncsocket 
        estabilished*: bool         #connection has started
        isfakessl*:bool             #broken ssl
        port*:uint32                #the port the socket points to

    Connections* = object
        connections*: seq[Connection]

var allConnections:seq[Connection]

var lgid: uint32 = 1 #last incremental global id 
proc new_uid: uint32 =
    result = lgid
    inc lgid

var et:uint = 0 #last epoch time

proc isTrusted*(con: Connection): bool = con.trusted == TrustStatus.yes

#send with a simple low cost timeout
template send*(con: Connection, data: string): untyped = 
    con.action_start_time = et
    var result = con.socket.send(data)
    result.addCallback(proc()=
        con.action_start_time = 0
    )
    result

#recv with a simple low cost timeout
template recv*(con: Connection, data: SomeInteger): untyped = 
    con.action_start_time = et
    var result = con.socket.recv(data)
    result.addCallback(proc()=
        con.action_start_time = 0
    )
    result

template isClosed*(con: Connection): bool = con.socket.isClosed()


proc prepairClose(con: Connection) = 
    if con.isfakessl:
        if con.isTrusted:
            con.socket.isSsl = true

proc close*(con: Connection) = 
    if not con.isClosed():
        prepairClose(con)
        con.socket.close()

        let i = allConnections.find(con)
        if i != -1:
            allConnections.del(i)


proc newConnection*(socket: AsyncSocket = nil, buffered: bool = globals.socket_buffered): Connection =
    new(result)
    result.id = new_uid()
    result.creation_time = epochTime().uint32
    result.trusted = TrustStatus.pending
    result.action_start_time = 0
    result.register_start_time = 0

    if socket == nil: result.socket = newAsyncSocket(buffered = buffered)
    else: result.socket = socket

    when not defined(android):
        if not globals.is_docker:
            result.socket.setSockOpt(OptNoDelay, true)
    allConnections.add result

proc grab*(cons: var Connections):Connection=
    if cons.connections.len() == 0: return nil
    result =  cons.connections[0]
    cons.connections.del(0)
    result.register_start_time = 0

proc register*(cons: var Connections, con: Connection) =  
    con.register_start_time = et
    cons.connections.add con

proc startController*(){.async.}=
    while true:
        et = epochTime().uint
        await sleepAsync(1000)

        allConnections.keepIf(
            proc(x: Connection):bool =
                if x.action_start_time != 0:
                    if et - x.action_start_time > globals.max_idle_time :
                        prepairClose(x)
                        x.socket.close()
                        if globals.log_conn_destory: echo "[Controller] closed a idle connection"
                        return false

                if x.register_start_time != 0:
                    if et - x.register_start_time > globals.max_pool_unused_time :
                        prepairClose(x)
                        x.socket.close()
                        if globals.log_conn_destory: echo "[Controller] closed a unused connection"
                        return false
                return true
        )
