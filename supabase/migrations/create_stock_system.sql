-- ===============================================
-- MIGRACIÓN: SISTEMA DE STOCK SORTLY-STYLE
-- ===============================================

-- Crear enums para el sistema de stock
CREATE TYPE tipo_ubicacion AS ENUM ('Almacen', 'Estante', 'Contenedor', 'Area', 'Equipo', 'Taller');
CREATE TYPE estado_ubicacion AS ENUM ('Activa', 'Inactiva', 'Mantenimiento');
CREATE TYPE estado_stock AS ENUM ('Disponible', 'Reservado', 'En_uso', 'Dañado', 'Vencido');
CREATE TYPE tipo_movimiento_stock AS ENUM ('Entrada', 'Salida', 'Transferencia', 'Ajuste', 'Asignacion');

-- ===============================================
-- TABLA: ubicaciones_stock
-- ===============================================
CREATE TABLE ubicaciones_stock (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    nombre TEXT NOT NULL,
    descripcion TEXT,
    codigo VARCHAR(50) UNIQUE NOT NULL,
    tipo tipo_ubicacion NOT NULL DEFAULT 'Almacen',
    estado estado_ubicacion NOT NULL DEFAULT 'Activa',
    parent_id UUID REFERENCES ubicaciones_stock(id) ON DELETE CASCADE,
    path TEXT, -- Path jerárquico para navegación
    color VARCHAR(20) DEFAULT '#3B82F6',
    icono VARCHAR(10) DEFAULT '📦',
    capacidad_maxima INTEGER,
    temperatura_min DECIMAL(5,2),
    temperatura_max DECIMAL(5,2),
    humedad_max DECIMAL(5,2),
    observaciones TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ===============================================
-- TABLA: stock_items
-- ===============================================
CREATE TABLE stock_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    codigo_item VARCHAR(50) UNIQUE NOT NULL,
    nombre TEXT NOT NULL,
    descripcion TEXT,
    marca VARCHAR(100),
    modelo VARCHAR(100),
    numero_serie VARCHAR(100),
    lote VARCHAR(100),
    cantidad_actual INTEGER NOT NULL DEFAULT 0 CHECK (cantidad_actual >= 0),
    cantidad_minima INTEGER NOT NULL DEFAULT 1 CHECK (cantidad_minima > 0),
    cantidad_maxima INTEGER CHECK (cantidad_maxima >= cantidad_minima),
    unidad_medida VARCHAR(20) DEFAULT 'unidad',
    estado estado_stock NOT NULL DEFAULT 'Disponible',
    ubicacion_id UUID REFERENCES ubicaciones_stock(id) ON DELETE SET NULL,
    categoria VARCHAR(100),
    subcategoria VARCHAR(100),
    proveedor VARCHAR(200),
    precio_unitario DECIMAL(12,2),
    moneda VARCHAR(3) DEFAULT 'USD',
    fecha_ingreso DATE DEFAULT CURRENT_DATE,
    fecha_vencimiento DATE,
    fecha_ultimo_movimiento TIMESTAMPTZ,
    fotos TEXT[], -- Array de URLs de fotos
    documentos TEXT[], -- Array de URLs de documentos
    tags TEXT[], -- Array de tags para búsqueda
    custom_fields JSONB DEFAULT '{}', -- Campos personalizados
    qr_code TEXT, -- Código QR generado
    barcode TEXT, -- Código de barras
    observaciones TEXT,
    activo BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ===============================================
-- TABLA: movimientos_stock
-- ===============================================
CREATE TABLE movimientos_stock (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    stock_item_id UUID NOT NULL REFERENCES stock_items(id) ON DELETE CASCADE,
    tipo_movimiento tipo_movimiento_stock NOT NULL,
    cantidad INTEGER NOT NULL CHECK (cantidad > 0),
    cantidad_anterior INTEGER NOT NULL,
    cantidad_nueva INTEGER NOT NULL,
    ubicacion_origen_id UUID REFERENCES ubicaciones_stock(id),
    ubicacion_destino_id UUID REFERENCES ubicaciones_stock(id),
    motivo TEXT NOT NULL,
    referencia_externa VARCHAR(100), -- Código de orden, factura, etc.
    usuario VARCHAR(100),
    costo_unitario DECIMAL(12,2),
    costo_total DECIMAL(12,2),
    fecha_movimiento TIMESTAMPTZ DEFAULT NOW(),
    observaciones TEXT,
    metadata JSONB DEFAULT '{}', -- Información adicional del movimiento
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ===============================================
-- TABLA: alertas_stock
-- ===============================================
CREATE TABLE alertas_stock (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    stock_item_id UUID NOT NULL REFERENCES stock_items(id) ON DELETE CASCADE,
    tipo_alerta VARCHAR(50) NOT NULL, -- 'stock_minimo', 'vencimiento', 'sin_movimiento', etc.
    titulo TEXT NOT NULL,
    mensaje TEXT NOT NULL,
    prioridad INTEGER DEFAULT 1 CHECK (prioridad BETWEEN 1 AND 5), -- 1=baja, 5=crítica
    estado VARCHAR(20) DEFAULT 'activa', -- 'activa', 'leida', 'resuelta', 'desactivada'
    fecha_limite DATE, -- Para alertas con fecha límite
    fecha_creacion TIMESTAMPTZ DEFAULT NOW(),
    fecha_leida TIMESTAMPTZ,
    fecha_resuelta TIMESTAMPTZ,
    resuelto_por VARCHAR(100),
    notas_resolucion TEXT,
    metadata JSONB DEFAULT '{}'
);

-- ===============================================
-- TABLA: componentes_disponibles (para migración)
-- ===============================================
-- Esta tabla ya existe, solo agregamos columnas necesarias si no existen
DO $$
BEGIN
    -- Verificar si la tabla componentes_disponibles ya existe
    IF EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'componentes_disponibles') THEN
        -- Agregar columnas faltantes si no existen
        ALTER TABLE componentes_disponibles 
        ADD COLUMN IF NOT EXISTS tags TEXT[] DEFAULT '{}',
        ADD COLUMN IF NOT EXISTS custom_fields JSONB DEFAULT '{}',
        ADD COLUMN IF NOT EXISTS ubicacion_stock_id UUID REFERENCES ubicaciones_stock(id),
        ADD COLUMN IF NOT EXISTS activo BOOLEAN DEFAULT TRUE;
    ELSE
        -- Crear tabla componentes_disponibles si no existe
        CREATE TABLE componentes_disponibles (
            id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            nombre TEXT NOT NULL,
            marca VARCHAR(100),
            modelo VARCHAR(100),
            numero_serie VARCHAR(100),
            cantidad_disponible INTEGER NOT NULL DEFAULT 0,
            estado VARCHAR(50) DEFAULT 'Activo',
            ubicacion_fisica TEXT DEFAULT 'Almacén General',
            proveedor VARCHAR(200),
            fecha_ingreso TIMESTAMPTZ DEFAULT NOW(),
            codigo_carga_origen VARCHAR(100),
            observaciones TEXT,
            tags TEXT[] DEFAULT '{}',
            custom_fields JSONB DEFAULT '{}',
            ubicacion_stock_id UUID REFERENCES ubicaciones_stock(id),
            activo BOOLEAN DEFAULT TRUE,
            created_at TIMESTAMPTZ DEFAULT NOW(),
            updated_at TIMESTAMPTZ DEFAULT NOW()
        );
    END IF;
END $$;

-- ===============================================
-- ÍNDICES PARA PERFORMANCE
-- ===============================================

-- Índices para ubicaciones_stock
CREATE INDEX idx_ubicaciones_codigo ON ubicaciones_stock(codigo);
CREATE INDEX idx_ubicaciones_tipo ON ubicaciones_stock(tipo);
CREATE INDEX idx_ubicaciones_estado ON ubicaciones_stock(estado);
CREATE INDEX idx_ubicaciones_parent ON ubicaciones_stock(parent_id);
CREATE INDEX idx_ubicaciones_path ON ubicaciones_stock(path);

-- Índices para stock_items
CREATE INDEX idx_stock_items_codigo ON stock_items(codigo_item);
CREATE INDEX idx_stock_items_nombre ON stock_items(nombre);
CREATE INDEX idx_stock_items_estado ON stock_items(estado);
CREATE INDEX idx_stock_items_ubicacion ON stock_items(ubicacion_id);
CREATE INDEX idx_stock_items_categoria ON stock_items(categoria);
CREATE INDEX idx_stock_items_fecha_vencimiento ON stock_items(fecha_vencimiento);
CREATE INDEX idx_stock_items_tags ON stock_items USING GIN(tags);
CREATE INDEX idx_stock_items_custom_fields ON stock_items USING GIN(custom_fields);
CREATE INDEX idx_stock_items_activo ON stock_items(activo);

-- Índices para movimientos_stock
CREATE INDEX idx_movimientos_stock_item ON movimientos_stock(stock_item_id);
CREATE INDEX idx_movimientos_tipo ON movimientos_stock(tipo_movimiento);
CREATE INDEX idx_movimientos_fecha ON movimientos_stock(fecha_movimiento);
CREATE INDEX idx_movimientos_usuario ON movimientos_stock(usuario);

-- Índices para alertas_stock
CREATE INDEX idx_alertas_stock_item ON alertas_stock(stock_item_id);
CREATE INDEX idx_alertas_tipo ON alertas_stock(tipo_alerta);
CREATE INDEX idx_alertas_estado ON alertas_stock(estado);
CREATE INDEX idx_alertas_prioridad ON alertas_stock(prioridad);
CREATE INDEX idx_alertas_fecha_creacion ON alertas_stock(fecha_creacion);

-- ===============================================
-- FUNCIONES AUXILIARES
-- ===============================================

-- Función para generar códigos de item únicos
CREATE OR REPLACE FUNCTION generar_codigo_item(prefijo TEXT DEFAULT 'ITM')
RETURNS TEXT AS $$
DECLARE
    nuevo_codigo TEXT;
    contador INTEGER := 1;
BEGIN
    LOOP
        nuevo_codigo := prefijo || '-' || LPAD(contador::TEXT, 6, '0');
        EXIT WHEN NOT EXISTS (SELECT 1 FROM stock_items WHERE codigo_item = nuevo_codigo);
        contador := contador + 1;
    END LOOP;
    RETURN nuevo_codigo;
END;
$$ LANGUAGE plpgsql;

-- Función para registrar movimientos automáticamente
CREATE OR REPLACE FUNCTION registrar_movimiento_stock()
RETURNS TRIGGER AS $$
BEGIN
    -- Solo registrar si la cantidad cambió
    IF OLD.cantidad_actual != NEW.cantidad_actual THEN
        INSERT INTO movimientos_stock (
            stock_item_id,
            tipo_movimiento,
            cantidad,
            cantidad_anterior,
            cantidad_nueva,
            motivo,
            usuario
        ) VALUES (
            NEW.id,
            CASE 
                WHEN NEW.cantidad_actual > OLD.cantidad_actual THEN 'Entrada'::tipo_movimiento_stock
                ELSE 'Salida'::tipo_movimiento_stock
            END,
            ABS(NEW.cantidad_actual - OLD.cantidad_actual),
            OLD.cantidad_actual,
            NEW.cantidad_actual,
            'Ajuste automático',
            'Sistema'
        );
    END IF;
    
    -- Actualizar fecha último movimiento
    NEW.fecha_ultimo_movimiento := NOW();
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Función para verificar alertas de stock
CREATE OR REPLACE FUNCTION verificar_alertas_stock()
RETURNS TRIGGER AS $$
BEGIN
    -- Alerta de stock mínimo
    IF NEW.cantidad_actual <= NEW.cantidad_minima THEN
        INSERT INTO alertas_stock (
            stock_item_id,
            tipo_alerta,
            titulo,
            mensaje,
            prioridad
        ) VALUES (
            NEW.id,
            'stock_minimo',
            'Stock Crítico: ' || NEW.nombre,
            'El item "' || NEW.nombre || '" tiene stock crítico (' || NEW.cantidad_actual || ' unidades, mínimo: ' || NEW.cantidad_minima || ')',
            CASE 
                WHEN NEW.cantidad_actual = 0 THEN 5
                WHEN NEW.cantidad_actual <= NEW.cantidad_minima / 2 THEN 4
                ELSE 3
            END
        )
        ON CONFLICT DO NOTHING; -- Evitar duplicados
    END IF;
    
    -- Alerta de vencimiento próximo (30 días)
    IF NEW.fecha_vencimiento IS NOT NULL AND NEW.fecha_vencimiento <= CURRENT_DATE + INTERVAL '30 days' THEN
        INSERT INTO alertas_stock (
            stock_item_id,
            tipo_alerta,
            titulo,
            mensaje,
            prioridad,
            fecha_limite
        ) VALUES (
            NEW.id,
            'vencimiento',
            'Próximo a Vencer: ' || NEW.nombre,
            'El item "' || NEW.nombre || '" vencerá el ' || NEW.fecha_vencimiento::TEXT,
            CASE 
                WHEN NEW.fecha_vencimiento <= CURRENT_DATE + INTERVAL '7 days' THEN 5
                WHEN NEW.fecha_vencimiento <= CURRENT_DATE + INTERVAL '15 days' THEN 4
                ELSE 3
            END,
            NEW.fecha_vencimiento
        )
        ON CONFLICT DO NOTHING;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ===============================================
-- TRIGGERS
-- ===============================================

-- Trigger para updated_at en ubicaciones_stock
CREATE TRIGGER update_ubicaciones_stock_updated_at
    BEFORE UPDATE ON ubicaciones_stock
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- Trigger para updated_at en stock_items
CREATE TRIGGER update_stock_items_updated_at
    BEFORE UPDATE ON stock_items
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- Trigger para registrar movimientos automáticamente
CREATE TRIGGER trigger_registrar_movimiento_stock
    BEFORE UPDATE ON stock_items
    FOR EACH ROW EXECUTE FUNCTION registrar_movimiento_stock();

-- Trigger para verificar alertas
CREATE TRIGGER trigger_verificar_alertas_stock
    AFTER INSERT OR UPDATE ON stock_items
    FOR EACH ROW EXECUTE FUNCTION verificar_alertas_stock();

-- ===============================================
-- VISTAS ÚTILES
-- ===============================================

-- Vista de stock crítico
CREATE VIEW vista_stock_critico AS
SELECT 
    si.*,
    ub.nombre as ubicacion_nombre,
    ub.codigo as ubicacion_codigo
FROM stock_items si
LEFT JOIN ubicaciones_stock ub ON si.ubicacion_id = ub.id
WHERE si.cantidad_actual <= si.cantidad_minima
  AND si.activo = TRUE
ORDER BY 
    CASE 
        WHEN si.cantidad_actual = 0 THEN 1
        WHEN si.cantidad_actual <= si.cantidad_minima / 2 THEN 2
        ELSE 3
    END,
    si.nombre;

-- Vista de movimientos recientes
CREATE VIEW vista_movimientos_recientes AS
SELECT 
    ms.*,
    si.nombre as item_nombre,
    si.codigo_item,
    uo.nombre as ubicacion_origen_nombre,
    ud.nombre as ubicacion_destino_nombre
FROM movimientos_stock ms
JOIN stock_items si ON ms.stock_item_id = si.id
LEFT JOIN ubicaciones_stock uo ON ms.ubicacion_origen_id = uo.id
LEFT JOIN ubicaciones_stock ud ON ms.ubicacion_destino_id = ud.id
ORDER BY ms.fecha_movimiento DESC;

-- Vista de alertas activas
CREATE VIEW vista_alertas_activas AS
SELECT 
    a.*,
    si.nombre as item_nombre,
    si.codigo_item,
    si.cantidad_actual,
    si.cantidad_minima,
    ub.nombre as ubicacion_nombre
FROM alertas_stock a
JOIN stock_items si ON a.stock_item_id = si.id
LEFT JOIN ubicaciones_stock ub ON si.ubicacion_id = ub.id
WHERE a.estado = 'activa'
ORDER BY a.prioridad DESC, a.fecha_creacion ASC;

-- Vista de stock por ubicación
CREATE VIEW vista_stock_por_ubicacion AS
SELECT 
    ub.id as ubicacion_id,
    ub.nombre as ubicacion_nombre,
    ub.codigo as ubicacion_codigo,
    ub.tipo as ubicacion_tipo,
    COUNT(si.id) as total_items,
    COUNT(CASE WHEN si.estado = 'Disponible' THEN 1 END) as items_disponibles,
    COUNT(CASE WHEN si.cantidad_actual <= si.cantidad_minima THEN 1 END) as items_stock_bajo,
    SUM(si.cantidad_actual) as cantidad_total,
    AVG(si.cantidad_actual) as promedio_cantidad
FROM ubicaciones_stock ub
LEFT JOIN stock_items si ON ub.id = si.ubicacion_id AND si.activo = TRUE
WHERE ub.estado = 'Activa'
GROUP BY ub.id, ub.nombre, ub.codigo, ub.tipo
ORDER BY ub.nombre;

-- ===============================================
-- RLS (Row Level Security)
-- ===============================================

-- Habilitar RLS en todas las tablas
ALTER TABLE ubicaciones_stock ENABLE ROW LEVEL SECURITY;
ALTER TABLE stock_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE movimientos_stock ENABLE ROW LEVEL SECURITY;
ALTER TABLE alertas_stock ENABLE ROW LEVEL SECURITY;

-- Políticas permisivas para desarrollo (AJUSTAR EN PRODUCCIÓN)
CREATE POLICY "Enable all operations for all users" ON ubicaciones_stock FOR ALL USING (true);
CREATE POLICY "Enable all operations for all users" ON stock_items FOR ALL USING (true);
CREATE POLICY "Enable all operations for all users" ON movimientos_stock FOR ALL USING (true);
CREATE POLICY "Enable all operations for all users" ON alertas_stock FOR ALL USING (true);

-- ===============================================
-- DATOS INICIALES
-- ===============================================

-- Insertar ubicaciones básicas
INSERT INTO ubicaciones_stock (nombre, descripcion, codigo, tipo, color, icono) VALUES
('Almacén Principal', 'Almacén principal de la empresa', 'ALM-001', 'Almacen', '#3B82F6', '🏢'),
('Taller Técnico', 'Área de reparación y mantenimiento', 'TAL-001', 'Taller', '#F59E0B', '🔨'),
('Equipos en Campo', 'Equipos instalados en clientes', 'CAM-001', 'Area', '#10B981', '📍'),
('Área de Cuarentena', 'Productos en revisión o cuarentena', 'CUA-001', 'Area', '#EF4444', '⚠️');

-- Función para migrar componentes existentes a stock_items
CREATE OR REPLACE FUNCTION migrar_componentes_a_stock()
RETURNS INTEGER AS $$
DECLARE
    componente RECORD;
    ubicacion_almacen UUID;
    contador INTEGER := 0;
BEGIN
    -- Obtener ID del almacén principal
    SELECT id INTO ubicacion_almacen FROM ubicaciones_stock WHERE codigo = 'ALM-001';
    
    -- Migrar cada componente
    FOR componente IN SELECT * FROM componentes_disponibles WHERE activo = TRUE
    LOOP
        INSERT INTO stock_items (
            codigo_item,
            nombre,
            marca,
            modelo,
            numero_serie,
            cantidad_actual,
            cantidad_minima,
            estado,
            ubicacion_id,
            proveedor,
            fecha_ingreso,
            custom_fields,
            tags,
            observaciones
        ) VALUES (
            COALESCE(componente.nombre, 'COMP') || '-' || LPAD(contador::TEXT, 4, '0'),
            componente.nombre,
            componente.marca,
            componente.modelo,
            componente.numero_serie,
            componente.cantidad_disponible,
            5, -- cantidad mínima por defecto
            CASE 
                WHEN componente.cantidad_disponible <= 5 THEN 'Stock Bajo'::estado_stock
                WHEN componente.estado = 'Activo' THEN 'Disponible'::estado_stock
                ELSE 'Dañado'::estado_stock
            END,
            ubicacion_almacen,
            componente.proveedor,
            componente.fecha_ingreso::DATE,
            JSONB_BUILD_OBJECT(
                'codigo_carga_origen', componente.codigo_carga_origen,
                'ubicacion_fisica_original', componente.ubicacion_fisica,
                'estado_original', componente.estado
            ),
            CASE 
                WHEN componente.nombre ILIKE '%ultraformer%' THEN ARRAY['ultraformer', 'facial']
                WHEN componente.nombre ILIKE '%cm%' OR componente.nombre ILIKE '%pieza%' THEN ARRAY['cm-slim', 'corporal']
                WHEN componente.nombre ILIKE '%venus%' THEN ARRAY['venus', 'mantenimiento']
                ELSE ARRAY['componente']
            END,
            componente.observaciones
        )
        ON CONFLICT (codigo_item) DO NOTHING;
        
        contador := contador + 1;
    END LOOP;
    
    RETURN contador;
END;
$$ LANGUAGE plpgsql;

-- ===============================================
-- COMENTARIOS FINALES
-- ===============================================

COMMENT ON TABLE ubicaciones_stock IS 'Ubicaciones físicas para organización jerárquica del stock';
COMMENT ON TABLE stock_items IS 'Items individuales del stock con trazabilidad completa';
COMMENT ON TABLE movimientos_stock IS 'Historial completo de todos los movimientos de stock';
COMMENT ON TABLE alertas_stock IS 'Sistema de alertas automáticas para gestión proactiva';

COMMENT ON VIEW vista_stock_critico IS 'Items con stock por debajo del mínimo establecido';
COMMENT ON VIEW vista_movimientos_recientes IS 'Movimientos de stock ordenados por fecha';
COMMENT ON VIEW vista_alertas_activas IS 'Alertas pendientes ordenadas por prioridad';
COMMENT ON VIEW vista_stock_por_ubicacion IS 'Resumen estadístico de stock por ubicación'; 