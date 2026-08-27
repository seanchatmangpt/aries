defmodule AriesPaaS.Solver do
  @moduledoc """
  Irreducible actuation adapter for the existing ARIES `aries-plan` binary.

  It does not interpret PDDL and does not decide authority. Every observed
  process execution, including non-zero exits, is coupled to a receipt.
  """

  import Bitwise

  @default_binary Path.expand("../../../target/debug/aries-plan", __DIR__)

  @spec solve(map()) :: {:ok, map()} | {:error, map()}
  def solve(request) do
    binary = Map.get(request, :binary) || System.get_env("ARIES_PLAN_BIN") || @default_binary
    domain_path = Map.fetch!(request, :domain_path)
    problem_path = Map.fetch!(request, :problem_path)

    with :ok <- executable(binary) do
      output_path =
        Path.join(
          System.tmp_dir!(),
          "aries-paas-#{System.unique_integer([:positive, :monotonic])}.plan"
        )

      args = [
        "--domain",
        domain_path,
        "--output",
        output_path,
        "--log-level",
        "error",
        problem_path
      ]

      started_at = DateTime.utc_now()

      try do
        {stdout, exit_code} = System.cmd(binary, args, stderr_to_stdout: true)
        ended_at = DateTime.utc_now()
        plan = read_optional(output_path)

        receipt =
          receipt(%{
            binary: binary,
            args: args,
            domain_path: domain_path,
            problem_path: problem_path,
            stdout: stdout,
            exit_code: exit_code,
            plan: plan,
            started_at: started_at,
            ended_at: ended_at
          })

        result = %{
          plan: plan,
          stdout: stdout,
          exit_code: exit_code,
          started_at: started_at,
          ended_at: ended_at,
          receipt: receipt
        }

        if exit_code == 0 do
          {:ok, result}
        else
          {:error,
           %{
             type: :aries_nonzero_exit,
             message: "ARIES returned non-zero exit status",
             result: result,
             receipt: receipt
           }}
        end
      after
        File.rm(output_path)
      end
    end
  end

  @spec sha256(binary()) :: String.t()
  def sha256(bytes) when is_binary(bytes) do
    :crypto.hash(:sha256, bytes)
    |> Base.encode16(case: :lower)
  end

  defp executable(path) do
    case File.stat(path) do
      {:ok, %File.Stat{type: :regular, mode: mode}} when band(mode, 0o111) != 0 ->
        :ok

      {:ok, _} ->
        {:error,
         %{
           type: :refused,
           reason: :aries_binary_not_executable,
           path: path
         }}

      {:error, reason} ->
        {:error,
         %{
           type: :refused,
           reason: :aries_binary_unavailable,
           path: path,
           os_reason: reason
         }}
    end
  end

  defp read_optional(path) do
    case File.read(path) do
      {:ok, bytes} -> bytes
      {:error, :enoent} -> nil
      {:error, reason} -> raise File.Error, reason: reason, action: "read plan", path: path
    end
  end

  defp receipt(execution) do
    domain_sha256 = execution.domain_path |> File.read!() |> sha256()
    problem_sha256 = execution.problem_path |> File.read!() |> sha256()
    command_sha256 = sha256(Enum.join([execution.binary | execution.args], <<0>>))
    plan_sha256 = if is_binary(execution.plan), do: sha256(execution.plan), else: nil
    stdout_sha256 = sha256(execution.stdout)

    standing =
      cond do
        execution.exit_code != 0 -> "BUILD_BROKEN"
        is_binary(execution.plan) -> "ALIVE"
        true -> "PARTIAL_ALIVE"
      end

    consequence_identity =
      [
        domain_sha256,
        problem_sha256,
        command_sha256,
        Integer.to_string(execution.exit_code),
        plan_sha256 || "no-plan",
        stdout_sha256
      ]
      |> Enum.join(":")
      |> sha256()

    %{
      receipt_version: "aries-paas/v1",
      receipt_id: consequence_identity,
      authority: "execute",
      domain_sha256: domain_sha256,
      problem_sha256: problem_sha256,
      command_sha256: command_sha256,
      plan_sha256: plan_sha256,
      stdout_sha256: stdout_sha256,
      exit_code: execution.exit_code,
      started_at: DateTime.to_iso8601(execution.started_at),
      ended_at: DateTime.to_iso8601(execution.ended_at),
      generated_at: DateTime.to_iso8601(execution.ended_at),
      standing: standing
    }
  end
end
