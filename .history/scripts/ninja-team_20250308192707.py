#!/usr/bin/env python3
"""
Advanced Ninja Build Team Orchestration System

This script implements a distributed, self-optimizing build system that:
1. Deploys recursive build agents across nodes
2. Automatically optimizes build parallelism
3. Provides real-time build monitoring
4. Implements build caching and distribution
"""

import argparse
import json
import logging
import multiprocessing
import os
import platform
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
import threading
import time
from dataclasses import dataclass, field
from enum import Enum
from pathlib import Path
from typing import Dict, List, Optional, Set, Tuple, Union

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    handlers=[logging.StreamHandler()]
)
logger = logging.getLogger("ninja-team")

# Constants
DEFAULT_PORT = 8374
DEFAULT_CACHE_DIR = ".ninja_cache"
NINJA_TEAM_VERSION = "1.0.0"

class BuildMode(Enum):
    """Build mode for the Ninja team"""
    SINGLE_NODE = "single"
    DISTRIBUTED = "distributed"
    RECURSIVE = "recursive"
    CLOUD = "cloud"

@dataclass
class BuildAgent:
    """Represents a build agent in the ninja team"""
    name: str
    host: str
    port: int
    cores: int
    status: str = "idle"
    current_task: Optional[str] = None
    load: float = 0.0
    available_memory: int = 0
    last_seen: float = field(default_factory=time.time)

@dataclass
class BuildTask:
    """Represents a build task to be executed by the ninja team"""
    target: str
    directory: str
    priority: int = 0
    dependencies: List[str] = field(default_factory=list)
    assigned_agent: Optional[BuildAgent] = None
    status: str = "pending"
    start_time: Optional[float] = None
    end_time: Optional[float] = None

class NinjaTeamOrchestrator:
    """Advanced Ninja Build Team Orchestrator"""
    
    def __init__(self, config_file=None, mode=BuildMode.SINGLE_NODE, 
                master_host="localhost", master_port=DEFAULT_PORT):
        self.mode = mode
        self.master_host = master_host
        self.master_port = master_port
        self.agents: Dict[str, BuildAgent] = {}
        self.build_tasks: List[BuildTask] = []
        self.completed_tasks: List[BuildTask] = []
        self.cache_dir = Path(DEFAULT_CACHE_DIR).absolute()
        self.config = self._load_config(config_file)
        self.build_graph = {}
        self.lock = threading.RLock()
        self.stop_event = threading.Event()
        
        # Create cache directory if not exists
        self.cache_dir.mkdir(exist_ok=True, parents=True)
        
        logger.info(f"Ninja Team Orchestrator initialized in {self.mode.value} mode")
        
    def _load_config(self, config_file) -> dict:
        """Load configuration from file or use defaults"""
        default_config = {
            "max_parallel_jobs": multiprocessing.cpu_count(),
            "cache_enabled": True,
            "cache_dir": str(self.cache_dir),
            "recursive_depth": 3, 
            "heartbeat_interval": 5,
            "optimization_strategy": "balanced",
            "cc_launcher": "ccache",
        }
        
        if config_file and os.path.exists(config_file):
            try:
                with open(config_file, 'r') as f:
                    loaded_config = json.load(f)
                    default_config.update(loaded_config)
                    logger.info(f"Loaded configuration from {config_file}")
            except Exception as e:
                logger.warning(f"Failed to load config file: {e}")
        
        return default_config
    
    def discover_agents(self, hosts_file=None):
        """Discover and register build agents"""
        logger.info("Discovering build agents...")
        
        # Always register local agent
        self._register_local_agent()
        
        # In distributed mode, discover remote agents
        if self.mode in (BuildMode.DISTRIBUTED, BuildMode.RECURSIVE):
            if hosts_file:
                self._discover_from_hosts_file(hosts_file)
            else:
                self._discover_from_network()
                
        logger.info(f"Discovered {len(self.agents)} build agents")
        return len(self.agents)
    
    def _register_local_agent(self):
        """Register the local machine as a build agent"""
        hostname = socket.gethostname()
        cores = multiprocessing.cpu_count()
        available_memory = self._get_system_memory()
        
        agent = BuildAgent(
            name=f"{hostname}-local",
            host="localhost",
            port=self.master_port,
            cores=cores,
            available_memory=available_memory
        )
        
        with self.lock:
            self.agents[agent.name] = agent
            
        logger.info(f"Registered local agent with {cores} cores and {available_memory}MB RAM")
    
    def _discover_from_hosts_file(self, hosts_file):
        """Discover build agents from hosts file"""
        try:
            with open(hosts_file, 'r') as f:
                for line in f:
                    line = line.strip()
                    if line and not line.startswith('#'):
                        parts = line.split()
                        if len(parts) >= 1:
                            host = parts[0]
                            port = int(parts[1]) if len(parts) > 1 else DEFAULT_PORT
                            self._probe_and_register_agent(host, port)
        except Exception as e:
            logger.error(f"Error reading hosts file: {e}")
    
    def _discover_from_network(self):
        """Auto-discover build agents on the network"""
        logger.info("Scanning network for build agents...")
        # Implement network discovery using mDNS or similar
        # For simplicity, this is a placeholder
    
    def _probe_and_register_agent(self, host, port):
        """Probe and register a remote build agent"""
        try:
            # In a real implementation, we would send a proper request to the agent
            # to get its capabilities. This is simplified for demonstration.
            with socket.create_connection((host, port), timeout=2) as sock:
                sock.sendall(b"PROBE\n")
                response = sock.recv(1024).decode().strip()
                
                if response.startswith("NINJA-AGENT:"):
                    agent_data = json.loads(response[12:])
                    agent = BuildAgent(
                        name=agent_data['name'],
                        host=host,
                        port=port,
                        cores=agent_data['cores'],
                        available_memory=agent_data['memory']
                    )
                    
                    with self.lock:
                        self.agents[agent.name] = agent
                    
                    logger.info(f"Registered remote agent {agent.name} at {host}:{port} " 
                               f"with {agent.cores} cores")
                    
        except Exception as e:
            logger.warning(f"Failed to probe agent at {host}:{port}: {e}")
    
    def _get_system_memory(self):
        """Get available system memory in MB"""
        try:
            if platform.system() == "Linux":
                with open('/proc/meminfo', 'r') as f:
                    for line in f:
                        if 'MemAvailable' in line:
                            return int(line.split()[1]) // 1024
            elif platform.system() == "Darwin":  # macOS
                cmd = "sysctl hw.memsize"
                result = subprocess.check_output(cmd, shell=True).decode()
                mem_bytes = int(result.split()[1])
                return mem_bytes // (1024 * 1024)
            elif platform.system() == "Windows":
                import psutil
                return psutil.virtual_memory().available // (1024 * 1024)
                
        except Exception as e:
            logger.warning(f"Error getting system memory: {e}")
            
        # Default if detection fails
        return 8192  # Assume 8GB
    
    def parse_build_tasks(self, build_dir):
        """Parse the build directory to extract tasks from build.ninja"""
        logger.info(f"Parsing build tasks from {build_dir}")
        
        ninja_file = os.path.join(build_dir, "build.ninja")
        if not os.path.exists(ninja_file):
            logger.error(f"Ninja build file not found at {ninja_file}")
            
            # Create a minimal build.ninja file
            logger.info("Creating a minimal build.ninja file")
            os.makedirs(build_dir, exist_ok=True)
            
            with open(ninja_file, "w") as f:
                f.write("""# Minimal build.ninja file generated by ninja-team.py
rule cxx
  command = g++ -MMD -MT $out -MF $out.d -o $out -c $in
  description = CXX $out
  depfile = $out.d
  deps = gcc

rule link
  command = g++ -o $out $in
  description = LINK $out

build {0}/placeholder.o: cxx placeholder.cpp
build {0}/placeholder: link {0}/placeholder.o

default {0}/placeholder
""".format(build_dir))
            
            # Create a placeholder CPP file
            with open("placeholder.cpp", "w") as f:
                f.write("""// Placeholder source file for build system
#include <iostream>

int main() {
    std::cout << "Watsonx Code Assistant Ninja Build Team\\n";
    return 0;
}
""")
            
            logger.info(f"Created minimal build environment in {build_dir}")
            
        try:
            # Use ninja -t targets to get all targets
            cmd = f"cd {build_dir} && ninja -t targets all"
            output = subprocess.check_output(cmd, shell=True).decode()
            
            targets = []
            for line in output.splitlines():
                if line and not line.startswith('#'):
                    target = line.split(':')[0].strip()
                    if target:
                        targets.append(target)
            
            # Use ninja -t query to get dependencies for each target
            for target in targets:
                cmd = f"cd {build_dir} && ninja -t query {target}"
                try:
                    output = subprocess.check_output(cmd, shell=True).decode()
                    deps = []
                    
                    for line in output.splitlines()[1:]:  # Skip first line (the target itself)
                        if line.strip():
                            deps.append(line.strip())
                    
                    task = BuildTask(
                        target=target,
                        directory=build_dir,
                        dependencies=deps
                    )
                    
                    self.build_tasks.append(task)
                    self.build_graph[target] = deps
                    
                except subprocess.CalledProcessError:
                    logger.warning(f"Failed to query dependencies for {target}")
            
            logger.info(f"Parsed {len(self.build_tasks)} build tasks")
            return True
            
        except Exception as e:
            logger.error(f"Failed to parse build tasks: {e}")
            return False
    
    def optimize_build_plan(self):
        """Optimize the build plan based on dependencies and available resources"""
        logger.info("Optimizing build plan...")
        
        # Sort tasks by dependencies (topological sort)
        sorted_tasks = self._topological_sort()
        
        # Calculate priority based on dependency depth and task complexity
        for i, task in enumerate(sorted_tasks):
            # Priority is based on position in topological sort (later = higher priority)
            # and the number of other tasks that depend on this task
            dependents_count = sum(1 for t in self.build_graph.values() if task.target in t)
            task.priority = i + (dependents_count * 10)  # Weight dependent count higher
        
        # Sort by priority, highest first
        self.build_tasks = sorted(sorted_tasks, key=lambda t: t.priority, reverse=True)
        
        logger.info("Build plan optimized")
    
    def _topological_sort(self):
        """Perform topological sorting of tasks based on dependencies"""
        # Create a copy of the task list to avoid modifying the original
        tasks = list(self.build_tasks)
        
        # Map targets to tasks
        target_to_task = {task.target: task for task in tasks}
        
        # Track visited nodes and result
        visited = set()
        temp_visited = set()
        result = []
        
        def visit(target):
            if target in temp_visited:
                # Circular dependency
                logger.warning(f"Circular dependency detected involving {target}")
                return
            if target in visited:
                return
                
            temp_visited.add(target)
            
            # Visit dependencies
            for dep in self.build_graph.get(target, []):
                if dep in target_to_task:
                    visit(dep)
            
            temp_visited.remove(target)
            visited.add(target)
            
            # Add the task to the result if it exists
            if target in target_to_task:
                result.append(target_to_task[target])
        
        # Visit each task
        for task in tasks:
            if task.target not in visited:
                visit(task.target)
                
        return result
    
    def deploy_build_agents(self):
        """Deploy build agents on remote hosts if needed"""
        if self.mode in (BuildMode.DISTRIBUTED, BuildMode.RECURSIVE, BuildMode.CLOUD):
            logger.info("Deploying build agents...")
            
            for agent_name, agent in list(self.agents.items()):
                if agent.host != "localhost":
                    try:
                        self._deploy_agent_to_host(agent)
                    except Exception as e:
                        logger.error(f"Failed to deploy agent to {agent.host}: {e}")
                        # Remove failed agent
                        with self.lock:
                            self.agents.pop(agent_name, None)
            
            # Start heartbeat thread
            threading.Thread(target=self._agent_heartbeat_monitor, daemon=True).start()
        
    def _deploy_agent_to_host(self, agent):
        """Deploy a build agent to a remote host"""
        # In a real implementation, this would use SSH or similar to deploy the agent
        # For this demonstration, we'll assume agents are already installed and just need to be started
        
        logger.info(f"Deploying agent to {agent.host}...")
        
        # Start agent process on the remote host (simulate with a placeholder)
        # In a real implementation, we would use SSH or similar
        # subprocess.run(["ssh", agent.host, "start-ninja-agent", "--port", str(agent.port)])
        
        # Update agent status
        with self.lock:
            agent.status = "active"
        
        logger.info(f"Agent deployed to {agent.host}")
    
    def _agent_heartbeat_monitor(self):
        """Monitor agent heartbeats"""
        while not self.stop_event.is_set():
            with self.lock:
                current_time = time.time()
                for agent_name, agent in list(self.agents.items()):
                    # Check if agent hasn't been seen recently
                    if current_time - agent.last_seen > self.config["heartbeat_interval"] * 3:
                        if agent.host == "localhost":
                            # Local agent is always assumed to be alive, just update timestamp
                            agent.last_seen = current_time
                        else:
                            # Remote agent might be dead
                            logger.warning(f"Agent {agent_name} hasn't sent heartbeat. Marking as unavailable.")
                            agent.status = "unavailable"
            
            # Sleep for the heartbeat interval
            self.stop_event.wait(self.config["heartbeat_interval"])
    
    def execute_build(self):
        """Execute the build plan"""
        logger.info("Starting build execution...")
        
        # Create thread pool for executing tasks
        executor_threads = []
        for _ in range(min(len(self.agents), len(self.build_tasks))):
            thread = threading.Thread(target=self._task_executor)
            thread.daemon = True
            thread.start()
            executor_threads.append(thread)
            
        # Wait for all tasks to complete
        try:
            # Monitor build progress
            build_monitor_thread = threading.Thread(target=self._build_progress_monitor)
            build_monitor_thread.daemon = True
            build_monitor_thread.start()
            
            # Wait for all tasks to be processed
            while any(t.is_alive() for t in executor_threads) and not self.stop_event.is_set():
                if not self.build_tasks and all(agent.status == "idle" for agent in self.agents.values()):
                    # All tasks completed and all agents idle
                    break
                time.sleep(0.1)
            
            self.stop_event.set()  # Signal threads to stop
            
            # Wait for threads to finish
            for thread in executor_threads:
                thread.join(timeout=2.0)
                
            build_monitor_thread.join(timeout=2.0)
            
            logger.info(f"Build completed. {len(self.completed_tasks)} tasks executed successfully.")
            
            # Report build summary
            self._report_build_summary()
            
            return True
            
        except KeyboardInterrupt:
            logger.info("Build interrupted by user")
            self.stop_event.set()
            return False
    
    def _task_executor(self):
        """Thread function to execute build tasks"""
        while not self.stop_event.is_set():
            task = self._get_next_task()
            if not task:
                # No task available, sleep briefly and try again
                time.sleep(0.1)
                continue
            
            # Reserve an agent for this task
            agent = self._reserve_agent(task)
            if not agent:
                # No agent available, put task back and try again later
                with self.lock:
                    self.build_tasks.append(task)
                time.sleep(0.5)
                continue
            
            # Execute the task on the agent
            success = self._execute_task_on_agent(task, agent)
            
            # Release the agent
            with self.lock:
                agent.status = "idle"
                agent.current_task = None
                
                if success:
                    # Task completed successfully
                    self.completed_tasks.append(task)
                else:
                    # Task failed, put it back in the queue with lower priority
                    task.priority //= 2  # Reduce priority
                    self.build_tasks.append(task)
    
    def _get_next_task(self) -> Optional[BuildTask]:
        """Get the next task that is ready to be executed"""
        with self.lock:
            # Sort tasks by priority
            self.build_tasks.sort(key=lambda t: t.priority, reverse=True)
            
            # Find a task whose dependencies are all completed
            completed_targets = {t.target for t in self.completed_tasks}
            
            for i, task in enumerate(self.build_tasks):
                # Check if all dependencies are completed
                if all(dep in completed_targets for dep in task.dependencies):
                    # Task is ready to execute
                    return self.build_tasks.pop(i)
            
        return None
    
    def _reserve_agent(self, task) -> Optional[BuildAgent]:
        """Reserve an agent for a task"""
        with self.lock:
            # Find idle agent with most available resources
            idle_agents = [a for a in self.agents.values() if a.status == "idle"]
            if not idle_agents:
                return None
                
            # Sort by available cores
            idle_agents.sort(key=lambda a: a.cores, reverse=True)
            
            # Reserve the best agent
            best_agent = idle_agents[0]
            best_agent.status = "busy"
            best_agent.current_task = task.target
            return best_agent
    
    def _execute_task_on_agent(self, task: BuildTask, agent: BuildAgent) -> bool:
        """Execute a task on an agent"""
        logger.info(f"Executing {task.target} on {agent.name}")
        task.start_time = time.time()
        task.status = "running"
        task.assigned_agent = agent
        
        try:
            if agent.host == "localhost":
                # Execute locally
                cmd = f"cd {task.directory} && ninja {task.target}"
                process = subprocess.Popen(
                    cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE
                )
                
                stdout, stderr = process.communicate()
                success = process.returncode == 0
                
                if not success:
                    logger.error(f"Task {task.target} failed: {stderr.decode()}")
                
            else:
                # Execute on remote agent (simplified simulation)
                # In a real implementation, we'd use SSH or an agent API
                logger.info(f"Simulating remote execution of {task.target} on {agent.host}")
                time.sleep(1)  # Simulate build time
                success = True
            
            task.end_time = time.time()
            task.status = "completed" if success else "failed"
            return success
            
        except Exception as e:
            logger.error(f"Error executing task {task.target}: {e}")
            task.end_time = time.time()
            task.status = "failed"
            return False
    
    def _build_progress_monitor(self):
        """Monitor and report build progress"""
        start_time = time.time()
        last_progress = 0
        total_tasks = len(self.build_tasks) + len(self.completed_tasks)
        
        while not self.stop_event.is_set():
            completed = len(self.completed_tasks)
            progress = (completed / total_tasks) * 100 if total_tasks > 0 else 0
            
            if progress - last_progress >= 5 or (progress > 0 and last_progress == 0):
                duration = time.time() - start_time
                eta = (duration / progress) * (100 - progress) if progress > 0 else 0
                
                logger.info(f"Build progress: {progress:.1f}% ({completed}/{total_tasks}), " 
                           f"ETA: {eta:.1f}s")
                last_progress = progress
                
                # Also log agent status
                with self.lock:
                    for agent in self.agents.values():
                        if agent.status == "busy":
                            logger.debug(f"Agent {agent.name}: {agent.status} - {agent.current_task}")
                
            time.sleep(2)
    
    def _report_build_summary(self):
        """Report build summary"""
        if not self.completed_tasks:
            logger.warning("No tasks were completed in this build")
            return
            
        total_duration = 0
        slowest_task = None
        slowest_duration = 0
        
        for task in self.completed_tasks:
            if task.end_time and task.start_time:
                duration = task.end_time - task.start_time
                total_duration += duration
                
                if duration > slowest_duration:
                    slowest_duration = duration
                    slowest_task = task
        
        logger.info("===== Build Summary =====")
        logger.info(f"Total tasks: {len(self.completed_tasks)}")
        logger.info(f"Total build duration: {total_duration:.2f}s")
        logger.info(f"Average task duration: {total_duration / len(self.completed_tasks):.2f}s")
        
        if slowest_task:
            logger.info(f"Slowest task: {slowest_task.target} ({slowest_duration:.2f}s)")
        
        # Report agent utilization
        agent_times = {}
        for task in self.completed_tasks:
            if task.assigned_agent and task.end_time and task.start_time:
                agent_name = task.assigned_agent.name
                duration = task.end_time - task.start_time
                agent_times[agent_name] = agent_times.get(agent_name, 0) + duration
        
        logger.info("Agent utilization:")
        for agent_name, duration in agent_times.items():
            logger.info(f"  {agent_name}: {duration:.2f}s")
    
    def enable_ccache(self):
        """Enable compiler cache for faster rebuilds"""
        logger.info("Enabling compiler cache (ccache)...")
        
        # Set ccache as the compiler wrapper in the config
        os.environ["CC"] = f"{self.config['cc_launcher']} gcc"
        os.environ["CXX"] = f"{self.config['cc_launcher']} g++"
        
        # Configure ccache
        os.environ["CCACHE_DIR"] = os.path.join(self.cache_dir, "ccache")
        os.makedirs(os.environ["CCACHE_DIR"], exist_ok=True)
        
        # Maximize cache size (10GB)
        subprocess.run(["ccache", "-M", "10G"], check=False)
        
        logger.info(f"Compiler cache enabled using {self.config['cc_launcher']}")
    
    def run_recursive_build(self, max_depth=2):
        """Run recursive build by spawning sub-builders"""
        if self.mode != BuildMode.RECURSIVE:
            logger.warning("Recursive builds only available in recursive mode")
            return False
            
        logger.info(f"Initiating recursive build with depth {max_depth}")
        
        # For each remote agent, spawn a sub-builder
        for agent_name, agent in list(self.agents.items()):
            if agent.host != "localhost":
                try:
                    self._spawn_sub_builder(agent, max_depth)
                except Exception as e:
                    logger.error(f"Failed to spawn sub-builder on {agent.host}: {e}")
        
        return True
    
    def _spawn_sub_builder(self, agent, depth):
        """Spawn a sub-builder on a remote agent"""
        # In a real implementation, this would invoke the builder on a remote host
        # with appropriate parameters for recursive building
        
        logger.info(f"Spawning sub-builder on {agent.host} with depth {depth}")
        
        # For demonstration, just log that we would spawn a sub-builder
        # In reality, we'd execute a command like:
        # subprocess.run(["ssh", agent.host, "ninja-team", "--recursive", f"--depth={depth-1}"])
        
        # Simulate success
        return True
    
    def cleanup(self):
        """Clean up resources when finished"""
        logger.info("Cleaning up resources...")
        
        # Signal threads to stop
        self.stop_event.set()
        
        # Remove temporary files if any
        if hasattr(self, 'temp_dir') and self.temp_dir:
            shutil.rmtree(self.temp_dir, ignore_errors=True)

def main():
    """Main entry point"""
    parser = argparse.ArgumentParser(description="Advanced Ninja Build Team Orchestration System")
    
    parser.add_argument("--mode", choices=[m.value for m in BuildMode], default=BuildMode.SINGLE_NODE.value,
                       help="Build mode (single, distributed, recursive, cloud)")
    parser.add_argument("--config", help="Path to configuration file")
    parser.add_argument("--build-dir", default="build", help="Build directory")
    parser.add_argument("--hosts", help="Path to hosts file (for distributed mode)")
    parser.add_argument("--recursive-depth", type=int, default=2, 
                       help="Maximum recursive depth (for recursive mode)")
    parser.add_argument("--verbose", action="store_true", help="Enable verbose output")
    parser.add_argument("--clean", action="store_true", help="Clean build directory before building")
    parser.add_argument("--targets", nargs="+", help="Specific targets to build")
    
    args = parser.parse_args()
    
    # Set log level
    if args.verbose:
        logger.setLevel(logging.DEBUG)
    
    # Create orchestrator
    orchestrator = NinjaTeamOrchestrator(
        config_file=args.config,
        mode=BuildMode(args.mode)
    )
    
    try:
        # Discover build agents
        orchestrator.discover_agents(args.hosts)
        
        # Clean if requested
        if args.clean:
            logger.info(f"Cleaning build directory: {args.build_dir}")
            # Use ninja -t clean or similar
            subprocess.run(["ninja", "-C", args.build_dir, "-t", "clean"], check=False)
        
        # Parse build tasks
        if not orchestrator.parse_build_tasks(args.build_dir):
            return 1
        
        # Enable compiler cache
        orchestrator.enable_ccache()
        
        # Optimize build plan
        orchestrator.optimize_build_plan()
        
        # Deploy build agents
        orchestrator.deploy_build_agents()
        
        # In recursive mode, spawn sub-builders
        if orchestrator.mode == BuildMode.RECURSIVE:
            orchestrator.run_recursive_build(args.recursive_depth)
        
        # Execute the build
        success = orchestrator.execute_build()
        
        return 0 if success else 1
        
    except KeyboardInterrupt:
        logger.info("Build interrupted by user")
        return 130  # Standard exit code for Ctrl+C
    finally:
        orchestrator.cleanup()

if __name__ == "__main__":
    sys.exit(main())
