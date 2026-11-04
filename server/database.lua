MZPropsDB = MZPropsDB or {}

local function ensureColumn(name, definition)
    local exists = MySQL.scalar.await([[
        SELECT COUNT(*)
        FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'mz_world_props' AND COLUMN_NAME = ?
    ]], { name })
    if tonumber(exists) == 0 then
        MySQL.query.await(('ALTER TABLE `mz_world_props` ADD COLUMN `%s` %s'):format(name, definition))
    end
end

function MZPropsDB.ensure()
    if not Config.AutoCreateTable then return end

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `mz_world_props` (
          `id` INT NOT NULL AUTO_INCREMENT,
          `name` VARCHAR(100) NOT NULL DEFAULT 'Prop sem nome',
          `model_hash` BIGINT NOT NULL,
          `model_name` VARCHAR(100) DEFAULT NULL,
          `x` DOUBLE NOT NULL,
          `y` DOUBLE NOT NULL,
          `z` DOUBLE NOT NULL,
          `rx` DOUBLE NOT NULL DEFAULT 0,
          `ry` DOUBLE NOT NULL DEFAULT 0,
          `rz` DOUBLE NOT NULL DEFAULT 0,
          `heading` DOUBLE NOT NULL DEFAULT 0,
          `frozen` TINYINT(1) NOT NULL DEFAULT 1,
          `collision_enabled` TINYINT(1) NOT NULL DEFAULT 1,
          `visible` TINYINT(1) NOT NULL DEFAULT 1,
          `created_by` VARCHAR(100) DEFAULT NULL,
          `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
          `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
          PRIMARY KEY (`id`),
          KEY `idx_model_hash` (`model_hash`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])

    ensureColumn('code', 'VARCHAR(64) DEFAULT NULL AFTER `name`')
    ensureColumn('stream_distance', ('DOUBLE NOT NULL DEFAULT %s AFTER `visible`'):format(
        tonumber(Config.StreamDistance) or 120.0
    ))
    ensureColumn('active', 'TINYINT(1) NOT NULL DEFAULT 1 AFTER `stream_distance`')
    ensureColumn('updated_by', 'VARCHAR(100) DEFAULT NULL AFTER `created_by`')
    ensureColumn('archived_by', 'VARCHAR(100) DEFAULT NULL AFTER `updated_by`')
    ensureColumn('archived_at', 'TIMESTAMP NULL DEFAULT NULL AFTER `archived_by`')
end

function MZPropsDB.fetchAll()
    return MySQL.query.await('SELECT * FROM mz_world_props ORDER BY id ASC') or {}
end

function MZPropsDB.insert(data)
    return MySQL.insert.await([[
        INSERT INTO mz_world_props
        (`name`, `code`, `model_hash`, `model_name`, `x`, `y`, `z`, `rx`, `ry`, `rz`, `heading`, `frozen`, `collision_enabled`, `visible`, `stream_distance`, `active`, `created_by`, `updated_by`)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]], {
        data.name,
        data.code or '',
        data.model_hash,
        data.model_name or '',
        data.x, data.y, data.z,
        data.rx or 0, data.ry or 0, data.rz or 0,
        data.heading or 0,
        data.frozen and 1 or 0,
        data.collision_enabled and 1 or 0,
        data.visible and 1 or 0,
        data.stream_distance or Config.StreamDistance,
        data.active ~= false and 1 or 0,
        data.created_by,
        data.updated_by or data.created_by
    })
end

function MZPropsDB.rename(id, name)
    MySQL.update.await('UPDATE mz_world_props SET name = ? WHERE id = ?', { name, id })
end

function MZPropsDB.delete(id)
    MySQL.update.await('DELETE FROM mz_world_props WHERE id = ?', { id })
end

function MZPropsDB.setFrozen(id, frozen)
    MySQL.update.await('UPDATE mz_world_props SET frozen = ? WHERE id = ?', { frozen and 1 or 0, id })
end

function MZPropsDB.setVisible(id, visible)
    MySQL.update.await('UPDATE mz_world_props SET visible = ? WHERE id = ?', { visible and 1 or 0, id })
end

function MZPropsDB.setStreamDistance(id, distance)
    MySQL.update.await('UPDATE mz_world_props SET stream_distance = ? WHERE id = ?', { distance, id })
end

function MZPropsDB.updateSettings(id, data, actor)
    return MySQL.update.await([[
        UPDATE mz_world_props
        SET name = ?, frozen = ?, collision_enabled = ?, visible = ?,
            stream_distance = ?, updated_by = ?
        WHERE id = ?
    ]], {
        data.name,
        data.frozen and 1 or 0,
        data.collision_enabled and 1 or 0,
        data.visible and 1 or 0,
        data.stream_distance,
        actor,
        id
    })
end

function MZPropsDB.setActive(id, active, actor)
    if active then
        return MySQL.update.await([[
            UPDATE mz_world_props
            SET active = 1, archived_by = NULL, archived_at = NULL, updated_by = ?
            WHERE id = ? AND active = 0
        ]], { actor, id })
    end
    return MySQL.update.await([[
        UPDATE mz_world_props
        SET active = 0, archived_by = ?, archived_at = UTC_TIMESTAMP(), updated_by = ?
        WHERE id = ? AND active = 1
    ]], { actor, actor, id })
end
