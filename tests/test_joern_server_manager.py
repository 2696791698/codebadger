from unittest.mock import MagicMock, patch

from src.models import Config
from src.services.joern_server_manager import JoernServerManager


def _make_container(host_port: int) -> MagicMock:
    container = MagicMock()
    container.attrs = {
        "NetworkSettings": {
            "Ports": {
                "13371/tcp": [
                    {
                        "HostIp": "0.0.0.0",
                        "HostPort": str(host_port),
                    }
                ]
            }
        }
    }
    return container


@patch("src.services.joern_server_manager.docker.from_env")
def test_spawn_server_uses_published_host_port(mock_from_env):
    docker_client = MagicMock()
    container = _make_container(host_port=23371)
    docker_client.containers.get.return_value = container
    mock_from_env.return_value = docker_client

    config = Config()
    config.joern.port_min = 13371
    config.joern.port_max = 13371
    config.joern.server_host = "127.0.0.1"

    manager = JoernServerManager(config=config)

    with patch.object(manager, "_ensure_port_free") as mock_ensure, patch.object(
        manager, "_wait_for_server", return_value=True
    ):
        host_port = manager.spawn_server("codebase-1")

    assert host_port == 23371
    assert manager.get_server_port("codebase-1") == 23371
    assert manager._container_ports["codebase-1"] == 13371
    mock_ensure.assert_called_once_with(container, 13371, 23371)

    exec_cmd = container.exec_run.call_args.kwargs["cmd"]
    assert "--server-port 13371" in exec_cmd[-1]


@patch("src.services.joern_server_manager.docker.from_env")
def test_terminate_server_kills_container_port_process(mock_from_env):
    docker_client = MagicMock()
    container = _make_container(host_port=23371)
    docker_client.containers.get.return_value = container
    mock_from_env.return_value = docker_client

    config = Config()
    config.joern.port_min = 13371
    config.joern.port_max = 13371
    config.joern.server_host = "127.0.0.1"

    manager = JoernServerManager(config=config)

    with patch.object(manager, "_ensure_port_free"), patch.object(
        manager, "_wait_for_server", return_value=True
    ):
        manager.spawn_server("codebase-1")

    container.exec_run.reset_mock()
    assert manager.terminate_server("codebase-1") is True

    kill_cmd = container.exec_run.call_args.kwargs["cmd"][-1]
    assert "--server-port 13371" in kill_cmd
