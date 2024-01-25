defmodule History.MixProject do
  use Mix.Project

  def project do
    [
      app: :iex_history,
      version: "4.2.0",
      elixir: "~> 1.16.0-otp-26",
      description: description(),
      package: package(),
      name: "IEx History",	
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:iex, :runtime_tools]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
     {:ex_doc, "~> 0.28.4", only: :dev, runtime: false},
     {:credo, "~> 1.7.3", only: [:dev, :test], runtime: false}
    ]
  end

  defp description() do
    "Saves shell history and variable bindings between shell sessions.

     Allows the user to display history in a more intuitive and cleaner way than the default.
  
     Historic actions can be viewed, replayed or copied. Scrolling through history is command, not line based."
  end

  defp package() do
    [
      files: ~w(lib .formatter.exs mix.exs README* LICENSE*),
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/nhpip/history"}
    ]
  end
end
