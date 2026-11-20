-- consommer.lua : retire une quantité d'ingrédient du stock d'un restaurant
-- en piochant d'abord dans le lot qui périme le plus tôt.
-- Tout s'exécute d'un bloc : aucune autre commande ne peut s'intercaler.
--
-- Usage : redis-cli --eval /scripts/consommer.lua , <resto> <ingredient> <quantite> [aujourdhui]
--   resto       : R01
--   ingredient  : poulet
--   quantite    : en grammes, entier > 0
--   aujourdhui  : optionnel, timestamp Unix de minuit UTC (pour les tests).
--                 Par défaut, l'heure du serveur Redis.
--
-- Retour : le nouveau total de l'ingrédient, ou une erreur si le stock est insuffisant.

local resto      = ARGV[1]
local ingredient = ARGV[2]
local quantite   = tonumber(ARGV[3])

if not resto or not ingredient or not quantite or quantite <= 0 then
  return redis.error_reply("usage : <resto> <ingredient> <quantite > 0> [aujourdhui]")
end

local aujourdhui = tonumber(ARGV[4])
if not aujourdhui then
  local t = tonumber(redis.call('TIME')[1])
  aujourdhui = t - (t % 86400)
end

local cle_total      = 'stock:' .. resto
local cle_lots       = 'stock:' .. resto .. ':' .. ingredient .. ':lots'
local cle_peremption = 'stock:' .. resto .. ':peremption'

-- 1. Les lots encore consommables (non périmés), du plus ancien au plus récent
local lots = redis.call('ZRANGE', cle_lots, aujourdhui, '+inf', 'BYSCORE')

-- 2. Vérifier qu'il y a assez avant de toucher à quoi que ce soit
local disponible = 0
for _, lot in ipairs(lots) do
  disponible = disponible + tonumber(redis.call('HGET', 'stock:' .. resto .. ':lot:' .. lot, 'quantite') or 0)
end
if disponible < quantite then
  return redis.error_reply('STOCK_INSUFFISANT ' .. resto .. ' ' .. ingredient ..
    ' : demandé ' .. quantite .. ', disponible ' .. disponible)
end

-- 3. Piocher lot par lot, le plus ancien d'abord
local reste = quantite
for _, lot in ipairs(lots) do
  if reste == 0 then break end
  local cle_lot = 'stock:' .. resto .. ':lot:' .. lot
  local q = tonumber(redis.call('HGET', cle_lot, 'quantite') or 0)
  local pris = math.min(q, reste)
  reste = reste - pris

  if pris == q then
    -- lot vidé : on le fait disparaître partout
    redis.call('DEL', cle_lot)
    redis.call('ZREM', cle_lots, lot)
    redis.call('ZREM', cle_peremption, lot)
  else
    redis.call('HINCRBY', cle_lot, 'quantite', -pris)
  end
end

-- 4. Mettre à jour le total
return redis.call('HINCRBY', cle_total, ingredient, -quantite)