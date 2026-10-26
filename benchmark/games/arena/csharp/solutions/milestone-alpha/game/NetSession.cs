namespace Glimmerpit;

using System;
using System.Collections.Generic;
using Godot;

/// <summary>
/// Carries the netcode over ENet: a server (hosted or dedicated) or a client. Messages are dictionaries turned into
/// var_to_bytes bytes by Wire (never objects, so nothing on the wire can run code) and sent with SendBytes: inputs unordered-latest on
/// channel 1, snapshots and the welcome reliable on channel 2. A hosted server's own player stays on its SimLink.
/// </summary>
public partial class NetSession : Node
{
    /// <summary>Players over ENet at most; a pit has four slots, and the rest are told it is full.</summary>
    public const int MaxClients = 8;
    public const int ChannelInput = 1;
    public const int ChannelState = 2;

    private SimLink? _link;
    private SceneMultiplayer? _multiplayer;
    private bool _closing;
    /// <summary>Which signals this session listens to: a server's ("host") or a client's ("join"); "" when closed.</summary>
    private string _role = "";

    public event Action? Connected;
    public event Action<string>? Disconnected;

    public ArenaServer? Server { get; private set; }
    public ArenaClient? Client { get; private set; }

    /// <summary>Listens on a port; peers wait for Serve() to give them a server.</summary>
    public Error Host(int port)
    {
        var peer = new ENetMultiplayerPeer();
        Error err = peer.CreateServer(port, MaxClients);
        if (err != Error.Ok)
            return err;
        _multiplayer = (SceneMultiplayer)Multiplayer;
        // Players never talk to each other, only to the server: without the relay the engine sends nobody news of other
        // peers, which it would also send to a peer still disconnecting (an engine error on its closed channels).
        _multiplayer.ServerRelay = false;
        _multiplayer.MultiplayerPeer = peer;
        _multiplayer.PeerConnected += OnPeerConnected;
        _multiplayer.PeerDisconnected += OnPeerDisconnected;
        _multiplayer.PeerPacket += OnPacket;
        _role = "host";
        return Error.Ok;
    }

    /// <summary>
    /// Serves a server to every ENet peer, those connected already included; peers on <paramref name="link"/> (a host's own
    /// player) stay on the link. A hosted rematch is a new server for the same peers.
    /// </summary>
    public void Serve(ArenaServer server, SimLink? link = null)
    {
        Server = server;
        _link = link;
        server.Send = SendFromServer;
        if (_multiplayer?.MultiplayerPeer is ENetMultiplayerPeer)
        {
            foreach (int peer in _multiplayer.GetPeers())
                server.PeerJoined(peer);
        }
    }

    /// <summary>Connects to a server; <paramref name="client"/> gets its messages once connected.</summary>
    public Error Join(string address, int port, ArenaClient? client = null)
    {
        var peer = new ENetMultiplayerPeer();
        Error err = peer.CreateClient(address, port);
        if (err != Error.Ok)
            return err;
        _multiplayer = (SceneMultiplayer)Multiplayer;
        _multiplayer.MultiplayerPeer = peer;
        _multiplayer.ConnectedToServer += OnConnected;
        _multiplayer.ConnectionFailed += OnFailed;
        _multiplayer.ServerDisconnected += OnServerLost;
        _multiplayer.PeerPacket += OnPacket;
        _role = "join";
        if (client != null)
            JoinWith(client);
        return Error.Ok;
    }

    /// <summary>Gives the connection to a (new) client.</summary>
    public void JoinWith(ArenaClient client)
    {
        Client = client;
        client.Send = SendToServer;
    }

    public bool IsOpen() =>
        _multiplayer?.MultiplayerPeer is ENetMultiplayerPeer enet && enet.GetConnectionStatus() != MultiplayerPeer.ConnectionStatus.Disconnected;

    public void Close()
    {
        _closing = true;
        if (_multiplayer != null)
        {
            if (_multiplayer.MultiplayerPeer is ENetMultiplayerPeer enet)
                enet.Close();
            // Only what this session connected: the engine reports a disconnect of anything else as an error.
            if (_role == "host")
            {
                _multiplayer.PeerConnected -= OnPeerConnected;
                _multiplayer.PeerDisconnected -= OnPeerDisconnected;
            }
            else if (_role == "join")
            {
                _multiplayer.ConnectedToServer -= OnConnected;
                _multiplayer.ConnectionFailed -= OnFailed;
                _multiplayer.ServerDisconnected -= OnServerLost;
            }
            if (_role != "")
                _multiplayer.PeerPacket -= OnPacket;
            _role = "";
            _multiplayer.MultiplayerPeer = new OfflineMultiplayerPeer();
            _multiplayer = null;
        }
        if (Client != null)
            Client.Send = null;
        _closing = false;
    }

    public override void _ExitTree()
    {
        Close();
    }

    private void OnPeerConnected(long peer) => Server?.PeerJoined((int)peer);

    private void OnPeerDisconnected(long peer) => Server?.PeerLeft((int)peer);

    private void OnPacket(long peer, byte[] packet)
    {
        object? message = Wire.Decode(packet);
        if (Server != null)
            Server.Receive((int)peer, message);
        else
            Client?.Receive(message);
    }

    private void OnConnected() => Connected?.Invoke();

    private void OnFailed() => OnLost("failed");

    private void OnServerLost() => OnLost("lost");

    private void OnLost(string reason)
    {
        if (!_closing)
            Disconnected?.Invoke(reason);
    }

    private void SendFromServer(int peer, Dictionary<string, object?> message)
    {
        if (_link != null && _link.HasPeer(peer))
            _link.Deliver(peer, message);
        else if (_multiplayer != null && Array.IndexOf(_multiplayer.GetPeers(), peer) >= 0)
            _multiplayer.SendBytes(Wire.Encode(message), peer, MultiplayerPeer.TransferModeEnum.Reliable, ChannelState);
    }

    private void SendToServer(Dictionary<string, object?> message)
    {
        if (_multiplayer?.MultiplayerPeer is ENetMultiplayerPeer enet && enet.GetConnectionStatus() == MultiplayerPeer.ConnectionStatus.Connected)
            _multiplayer.SendBytes(Wire.Encode(message), 1, MultiplayerPeer.TransferModeEnum.UnreliableOrdered, ChannelInput);
    }
}
