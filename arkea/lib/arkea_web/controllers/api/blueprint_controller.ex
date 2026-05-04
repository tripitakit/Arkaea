defmodule ArkeaWeb.API.BlueprintController do
  @moduledoc """
  Read-only export of an `ArkeonBlueprint` (UI Phase F).

  Endpoint:

  - `GET /api/blueprints/:id.json` — blueprint metadata + decoded
    genome ready for off-line analysis. Players can only export
    blueprints linked to one of their own home biotopes; cross-player
    exports are blocked with HTTP 404 (rather than 403, to avoid
    leaking the existence of other players' blueprints).
  """
  use ArkeaWeb, :controller

  import Ecto.Query

  alias Arkea.Persistence.ArkeonBlueprint
  alias Arkea.Persistence.PlayerBiotope
  alias Arkea.Repo

  def show(conn, %{"id" => blueprint_id}) do
    player_id = conn.assigns.current_player.id

    with %ArkeonBlueprint{} = blueprint <- get_blueprint(blueprint_id),
         true <- owned_by?(blueprint, player_id),
         {:ok, genome} <- ArkeonBlueprint.load_genome(blueprint.genome_binary) do
      payload = %{
        id: blueprint.id,
        name: blueprint.name,
        starter_archetype: blueprint.starter_archetype,
        phenotype_spec: blueprint.phenotype_spec,
        genome: genome_export(genome),
        inserted_at: blueprint.inserted_at,
        updated_at: blueprint.updated_at
      }

      conn
      |> put_resp_header(
        "content-disposition",
        ~s|attachment; filename="blueprint-#{blueprint.id}.json"|
      )
      |> json(payload)
    else
      _ ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Blueprint not found."})
    end
  end

  defp get_blueprint(id) when is_binary(id) do
    Repo.get(ArkeonBlueprint, id)
  rescue
    Ecto.Query.CastError -> nil
  end

  defp owned_by?(%ArkeonBlueprint{id: _bid, player_id: pid}, player_id) when pid == player_id do
    true
  end

  defp owned_by?(%ArkeonBlueprint{id: bid}, player_id) do
    # Fall back to player_biotope ownership in case the legacy
    # blueprint table was created with a null `player_id` (early
    # prototype rows).
    Repo.exists?(
      from pb in PlayerBiotope,
        where: pb.source_blueprint_id == ^bid and pb.player_id == ^player_id
    )
  end

  defp owned_by?(_, _), do: false

  defp genome_export(genome) do
    %{
      gene_count: genome.gene_count,
      chromosome:
        Enum.map(genome.chromosome, fn gene ->
          %{
            id: gene.id,
            domains:
              Enum.map(gene.domains, fn domain ->
                %{
                  type: domain.type,
                  type_tag: domain.type_tag,
                  parameter_codons: domain.parameter_codons,
                  params: domain.params
                }
              end),
            intergenic_blocks: Map.get(gene, :intergenic_blocks, %{})
          }
        end),
      plasmids:
        Enum.map(genome.plasmids, fn plasmid ->
          %{
            inc_group: Map.get(plasmid, :inc_group),
            copy_number: Map.get(plasmid, :copy_number),
            oriT_present: Map.get(plasmid, :oriT_present),
            genes: Enum.map(plasmid.genes, &gene_summary/1)
          }
        end),
      prophages:
        Enum.map(genome.prophages, fn prophage ->
          %{
            state: Map.get(prophage, :state),
            repressor_strength: Map.get(prophage, :repressor_strength),
            genes: Enum.map(prophage.genes, &gene_summary/1)
          }
        end)
    }
  end

  defp gene_summary(gene) do
    %{
      id: gene.id,
      domain_types: Enum.map(gene.domains, & &1.type)
    }
  end
end
