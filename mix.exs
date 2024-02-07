defmodule IExHistory2.MixProject do
  use Mix.Project

  def project do
    [
      app: :iex_history2,
      version: "5.3.2",
      elixir: "~> 1.16.0-otp-26",
      description: description(),
      package: package(),
      name: "IExHistory2",	
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      mod: {IExHistory2, []},
      extra_applications: [:iex, :runtime_tools]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
     {:ex_doc, "~> 0.31", only: :dev, runtime: false},
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
      links: %{"GitHub" => "https://github.com/nhpip/iex_history2"}
    ]
  end
end
