-- purger_perimes.lua : retire du stock d'un restaurant tous les lots périmés.
-- À lancer chaque nuit, pour chaque restaurant.
--
-- Usage : redis-cli --eval /scripts/purger_perimes.lua , <resto> [aujourdhui]
--   aujourdhui : optionnel, timestamp Unix de minuit UTC (pour les tests).
--                Par défaut, l'heure du serveur Redis.
--
-- Un lot est périmé si sa date de péremption est strictement avant aujourd'hui.
-- Retour : le nombre de lots retirés.

local resto = ARGV[1]
if not resto then
  return redis.error_reply("usage : <resto> [aujourdhui]")
end

local aujourdhui = tonumber(ARGV[2])
if not aujourdhui then
  local t = tonumber(redis.call('TIME')[1])
  aujourdhui = t - (t % 86400)
end

local cle_total      = 'stock:' .. resto
local cle_peremption = 'stock:' .. resto .. ':peremption'

-- "(" = borne exclue : tout ce qui est strictement avant aujourd'hui
local perimes = redis.call('ZRANGE', cle_peremption, '-inf', '(' .. aujourdhui, 'BYSCORE')

for _, lot in ipairs(perimes) do
  local cle_lot = 'stock:' .. resto .. ':lot:' .. lot
  local ingredient = redis.call('HGET', cle_lot, 'ingredient')
  local q = tonumber(redis.call('HGET', cle_lot, 'quantite') or 0)

  if ingredient then
    redis.call('HINCRBY', cle_total, ingredient, -q)
    redis.call('ZREM', 'stock:' .. resto .. ':' .. ingredient .. ':lots', lot)
  end
  redis.call('ZREM', cle_peremption, lot)
  redis.call('DEL', cle_lot)
end

return #perimes