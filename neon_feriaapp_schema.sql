--
-- PostgreSQL database dump
--

\restrict 7psm3cgXQJL69hUfCU4dyVaTroj31nCNrGJyOHf6JWZKPw5dUh37MvlwgLoV7Zj

-- Dumped from database version 18.4 (eaf151e)
-- Dumped by pg_dump version 18.4 (Debian 18.4-1.pgdg13+1)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: pgcrypto; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA public;


--
-- Name: EXTENSION pgcrypto; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION pgcrypto IS 'cryptographic functions';


--
-- Name: uuid-ossp; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA public;


--
-- Name: EXTENSION "uuid-ossp"; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION "uuid-ossp" IS 'generate universally unique identifiers (UUIDs)';


--
-- Name: calcular_precio_sugerido(integer, character varying); Type: FUNCTION; Schema: public; Owner: neondb_owner
--

CREATE FUNCTION public.calcular_precio_sugerido(p_producto_id integer, p_canal character varying) RETURNS integer
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_precio INTEGER;
    v_nivel VARCHAR(30);
    v_temporadas INTEGER;
BEGIN
    SELECT nivel_calidad_id, temporadas_en_inventario 
    INTO v_nivel, v_temporadas
    FROM productos WHERE id = p_producto_id;
    
    SELECT COALESCE(
        CASE p_canal
            WHEN 'online' THEN precio_online
            WHEN 'feria' THEN precio_feria
            WHEN 'retazo' THEN precio_standard * 0.2
            ELSE precio_standard
        END,
        precio_standard,
        0
    ) INTO v_precio
    FROM productos WHERE id = p_producto_id;
    
    IF p_canal = 'feria' AND v_temporadas > 2 THEN
        v_precio := v_precio * (1 - (FLOOR(v_temporadas::FLOAT / 2) * 0.1));
    END IF;
    
    RETURN GREATEST(v_precio, 0)::INTEGER;
END;
$$;


ALTER FUNCTION public.calcular_precio_sugerido(p_producto_id integer, p_canal character varying) OWNER TO neondb_owner;

--
-- Name: incrementar_temporada_inventario(); Type: FUNCTION; Schema: public; Owner: neondb_owner
--

CREATE FUNCTION public.incrementar_temporada_inventario() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF OLD.temporada_id IS DISTINCT FROM NEW.temporada_id AND NEW.temporada_id IS NOT NULL THEN
        NEW.temporadas_en_inventario = COALESCE(OLD.temporadas_en_inventario, 0) + 1;
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.incrementar_temporada_inventario() OWNER TO neondb_owner;

--
-- Name: mover_prenda_canal(integer, character varying, character varying, text, integer); Type: FUNCTION; Schema: public; Owner: neondb_owner
--

CREATE FUNCTION public.mover_prenda_canal(p_producto_id integer, p_canal_origen character varying, p_canal_destino character varying, p_motivo text, p_usuario_id integer) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
    INSERT INTO flujo_prenda (
        producto_id, canal_origen, canal_destino, 
        nivel_calidad_origen_id, nivel_calidad_destino_id,
        motivo, evaluado_por_id
    ) VALUES (
        p_producto_id, p_canal_origen, p_canal_destino,
        (SELECT nivel_calidad_id FROM productos WHERE id = p_producto_id),
        NULL,
        p_motivo, p_usuario_id
    );
    
    UPDATE productos SET 
        estado = CASE 
            WHEN p_canal_destino = 'retazo' THEN 'retazo'
            WHEN p_canal_destino = 'online' THEN 'disponible'
            WHEN p_canal_destino = 'feria' THEN 'disponible'
            ELSE estado
        END,
        updated_at = NOW()
    WHERE id = p_producto_id;
END;
$$;


ALTER FUNCTION public.mover_prenda_canal(p_producto_id integer, p_canal_origen character varying, p_canal_destino character varying, p_motivo text, p_usuario_id integer) OWNER TO neondb_owner;

--
-- Name: reconstruir_ventas_historicas(); Type: FUNCTION; Schema: public; Owner: neondb_owner
--

CREATE FUNCTION public.reconstruir_ventas_historicas() RETURNS TABLE(res_tipo text, res_total bigint)
    LANGUAGE plpgsql
    AS $_$
DECLARE
    v_evento_id bigint;
    v_venta_id bigint;
    v_linea_id bigint;
BEGIN
    -- VENTA 1: Online 18 junio (Calefón)
    INSERT INTO eventos_feria (canal_venta_id, fecha, lugar, vendedor_principal_id, estado, total_calculado, notas, created_at)
    VALUES ((SELECT cv.id FROM canales_venta cv WHERE cv.tipo = 'online'), '2026-06-18', 'Marketplace/Facebook', 2, 'cerrado', 35000, 'Evento reconstruido desde memoria. Venta online.', NOW())
    RETURNING eventos_feria.id INTO v_evento_id;

    INSERT INTO journal_ventas (evento_feria_id, usuario_id, dispositivo_id, timestamp_local, forma_pago, estado_pago, total_venta, precio_standard_total, precio_final_total, diferencia_rebaja, porcentaje_rebaja, tipo_rebaja, motivo_rebaja, venta_directa_sin_bodega, sync_estado, notas, created_at)
    VALUES (v_evento_id, 2, 1, '2026-06-18 14:00:00', 'transferencia', 'pagado', 35000, 35000, 35000, 0, 0.00, 'ninguna', NULL, TRUE, 'sincronizado', 'RECONSTRUIDO: Calefón Junkers 13 litro usado. Detalle: piloto. Publicado $35000, vendido $35000.', NOW())
    RETURNING journal_ventas.id INTO v_venta_id;

    INSERT INTO lineas_venta (venta_id, producto_id, cantidad, precio_unitario_standard, precio_unitario_final, subtotal, notas)
    VALUES (v_venta_id, 57, 1, 35000, 35000, 35000, 'Calefón Junkers 13 litro usado. Detalle piloto.');

    -- VENTA 2: Online 20 junio (Alero PVC + rebaja por retiro en casa)
    INSERT INTO eventos_feria (canal_venta_id, fecha, lugar, vendedor_principal_id, estado, total_calculado, notas, created_at)
    VALUES ((SELECT cv.id FROM canales_venta cv WHERE cv.tipo = 'online'), '2026-06-20', 'Marketplace/Facebook - Retiro en casa', 2, 'cerrado', 30000, 'Evento reconstruido desde memoria. Venta online con rebaja.', NOW())
    RETURNING eventos_feria.id INTO v_evento_id;

    INSERT INTO journal_ventas (evento_feria_id, usuario_id, dispositivo_id, timestamp_local, forma_pago, estado_pago, total_venta, precio_standard_total, precio_final_total, diferencia_rebaja, porcentaje_rebaja, tipo_rebaja, motivo_rebaja, venta_directa_sin_bodega, sync_estado, notas, created_at)
    VALUES (v_evento_id, 2, 1, '2026-06-20 16:00:00', 'transferencia', 'pagado', 30000, 35000, 30000, -5000, 14.29, 'otro', 'Rebaja por retiro en casa (no cliente frecuente)', TRUE, 'sincronizado', 'RECONSTRUIDO: Alero PVC 1.20x1m usado con detalles. Publicado $35000, vendido $30000 (rebaja $5000). Retiro en casa.', NOW())
    RETURNING journal_ventas.id INTO v_venta_id;

    INSERT INTO lineas_venta (venta_id, producto_id, cantidad, precio_unitario_standard, precio_unitario_final, subtotal, notas)
    VALUES (v_venta_id, 57, 1, 35000, 30000, 30000, 'Alero PVC 1.20x1m usado con detalles. Rebaja por retiro en casa.')
    RETURNING lineas_venta.id INTO v_linea_id;

    INSERT INTO venta_rebajas (venta_id, linea_venta_id, precio_standard, precio_final, tipo_rebaja, nota_rebaja)
    VALUES (v_venta_id, v_linea_id, 35000, 30000, 'otro', 'Rebaja por retiro en casa (no cliente frecuente)');

    -- VENTA 3: Directo 15 mayo (Chaqueta Mujer)
    INSERT INTO eventos_feria (canal_venta_id, fecha, lugar, vendedor_principal_id, estado, total_calculado, notas, created_at)
    VALUES ((SELECT cv.id FROM canales_venta cv WHERE cv.tipo = 'presencial_directo'), '2026-05-15', 'Auto - Apoderados colegio', 2, 'cerrado', 4000, 'Evento reconstruido desde memoria. Venta directa.', NOW())
    RETURNING eventos_feria.id INTO v_evento_id;

    INSERT INTO journal_ventas (evento_feria_id, usuario_id, dispositivo_id, timestamp_local, forma_pago, estado_pago, total_venta, precio_standard_total, precio_final_total, diferencia_rebaja, porcentaje_rebaja, tipo_rebaja, motivo_rebaja, venta_directa_sin_bodega, sync_estado, notas, created_at)
    VALUES (v_evento_id, 2, 1, '2026-05-15 12:00:00', 'efectivo', 'pagado', 4000, 4000, 4000, 0, 0.00, 'ninguna', NULL, TRUE, 'sincronizado', 'RECONSTRUIDO: Chaqueta Mujer. Venta directa a apoderados. Esposa llevaba ropa en auto.', NOW())
    RETURNING journal_ventas.id INTO v_venta_id;

    INSERT INTO lineas_venta (venta_id, producto_id, cantidad, precio_unitario_standard, precio_unitario_final, subtotal, notas)
    VALUES (v_venta_id, 21, 1, 4000, 4000, 4000, 'Chaqueta Mujer. Venta directa apoderados.');

    RETURN QUERY
    SELECT 'Eventos reconstruidos'::text, COUNT(*)::bigint FROM eventos_feria ef WHERE ef.notas LIKE '%reconstruido%'
    UNION ALL
    SELECT 'Ventas reconstruidas', COUNT(*) FROM journal_ventas jv WHERE jv.notas LIKE '%RECONSTRUIDO%'
    UNION ALL
    SELECT 'Lineas reconstruidas', COUNT(*) FROM lineas_venta lv WHERE lv.notas LIKE '%reconstruido%'
    UNION ALL
    SELECT 'Rebajas reconstruidas', COUNT(*) FROM venta_rebajas vr WHERE vr.nota_rebaja LIKE '%reconstruido%';
END;
$_$;


ALTER FUNCTION public.reconstruir_ventas_historicas() OWNER TO neondb_owner;

--
-- Name: revocar_tokens_anteriores(); Type: FUNCTION; Schema: public; Owner: neondb_owner
--

CREATE FUNCTION public.revocar_tokens_anteriores() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    UPDATE refresh_tokens
    SET revocado = TRUE
    WHERE dispositivo_id = NEW.dispositivo_id
      AND id != NEW.id
      AND usado_en IS NULL;
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.revocar_tokens_anteriores() OWNER TO neondb_owner;

--
-- Name: update_productos_updated_at(); Type: FUNCTION; Schema: public; Owner: neondb_owner
--

CREATE FUNCTION public.update_productos_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.update_productos_updated_at() OWNER TO neondb_owner;

--
-- Name: validar_cierre_evento(); Type: FUNCTION; Schema: public; Owner: neondb_owner
--

CREATE FUNCTION public.validar_cierre_evento() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF NEW.estado = 'cerrado' AND OLD.estado != 'cerrado' THEN
        IF NEW.revisado_por_id IS NULL THEN
            RAISE EXCEPTION 'No se puede cerrar evento sin revisión manual. Asigne revisado_por_id.';
        END IF;
        IF NEW.total_confirmado IS NULL THEN
            RAISE EXCEPTION 'No se puede cerrar evento sin total_confirmado. Revise manualmente.';
        END IF;
        NEW.fecha_cierre = NOW();
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.validar_cierre_evento() OWNER TO neondb_owner;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: canales_venta; Type: TABLE; Schema: public; Owner: neondb_owner
--

CREATE TABLE public.canales_venta (
    id integer NOT NULL,
    nombre character varying(100) NOT NULL,
    tipo character varying(30) NOT NULL,
    descripcion text,
    activo boolean DEFAULT true,
    fecha_inicio date,
    fecha_cierre date,
    created_at timestamp with time zone DEFAULT now(),
    CONSTRAINT canales_venta_tipo_check CHECK (((tipo)::text = ANY ((ARRAY['feria_dominical'::character varying, 'feria_chic'::character varying, 'feria_artesanal'::character varying, 'feria_navidena'::character varying, 'feria_cerrada'::character varying, 'instagram'::character varying, 'marketplace'::character varying, 'presencial_stgo'::character varying, 'presencial_directo'::character varying, 'online'::character varying])::text[])))
);


ALTER TABLE public.canales_venta OWNER TO neondb_owner;

--
-- Name: canales_venta_id_seq; Type: SEQUENCE; Schema: public; Owner: neondb_owner
--

CREATE SEQUENCE public.canales_venta_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.canales_venta_id_seq OWNER TO neondb_owner;

--
-- Name: canales_venta_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: neondb_owner
--

ALTER SEQUENCE public.canales_venta_id_seq OWNED BY public.canales_venta.id;


--
-- Name: categoria_canal; Type: TABLE; Schema: public; Owner: neondb_owner
--

CREATE TABLE public.categoria_canal (
    categoria_id integer NOT NULL,
    canal_id integer NOT NULL
);


ALTER TABLE public.categoria_canal OWNER TO neondb_owner;

--
-- Name: categorias_producto; Type: TABLE; Schema: public; Owner: neondb_owner
--

CREATE TABLE public.categorias_producto (
    id integer NOT NULL,
    nombre character varying(100) NOT NULL,
    sector_puesto character varying(20) NOT NULL,
    tipo_origen character varying(20) NOT NULL,
    activo boolean DEFAULT true,
    CONSTRAINT categorias_producto_sector_puesto_check CHECK (((sector_puesto)::text = ANY ((ARRAY['infantil'::character varying, 'alimentos'::character varying, 'hombres'::character varying, 'mujeres'::character varying, 'accesorios'::character varying, 'fondo'::character varying, 'artesania'::character varying, 'sin_sector'::character varying])::text[]))),
    CONSTRAINT categorias_producto_tipo_origen_check CHECK (((tipo_origen)::text = ANY ((ARRAY['propio'::character varying, 'vecino'::character varying, 'reventa'::character varying, 'donacion'::character varying, 'huerta'::character varying])::text[])))
);


ALTER TABLE public.categorias_producto OWNER TO neondb_owner;

--
-- Name: categorias_producto_id_seq; Type: SEQUENCE; Schema: public; Owner: neondb_owner
--

CREATE SEQUENCE public.categorias_producto_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.categorias_producto_id_seq OWNER TO neondb_owner;

--
-- Name: categorias_producto_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: neondb_owner
--

ALTER SEQUENCE public.categorias_producto_id_seq OWNED BY public.categorias_producto.id;


--
-- Name: categorias_ropa; Type: TABLE; Schema: public; Owner: neondb_owner
--

CREATE TABLE public.categorias_ropa (
    id integer NOT NULL,
    codigo character varying(30) NOT NULL,
    nombre character varying(100) NOT NULL,
    grupo character varying(50) NOT NULL,
    descripcion text,
    activo boolean DEFAULT true,
    CONSTRAINT categorias_ropa_grupo_check CHECK (((grupo)::text = ANY ((ARRAY['ropa_base'::character varying, 'accesorios_textiles'::character varying, 'accesorios_cuero'::character varying, 'calzado'::character varying, 'joyeria_bijouteria'::character varying, 'juguetes'::character varying, 'hogar_cultura'::character varying, 'bebe'::character varying])::text[])))
);


ALTER TABLE public.categorias_ropa OWNER TO neondb_owner;

--
-- Name: categorias_ropa_id_seq; Type: SEQUENCE; Schema: public; Owner: neondb_owner
--

CREATE SEQUENCE public.categorias_ropa_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.categorias_ropa_id_seq OWNER TO neondb_owner;

--
-- Name: categorias_ropa_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: neondb_owner
--

ALTER SEQUENCE public.categorias_ropa_id_seq OWNED BY public.categorias_ropa.id;


--
-- Name: clientes_frecuentes; Type: TABLE; Schema: public; Owner: neondb_owner
--

CREATE TABLE public.clientes_frecuentes (
    id integer NOT NULL,
    nombre character varying(100) NOT NULL,
    contacto character varying(100),
    perfil character varying(20) DEFAULT 'sin_definir'::character varying,
    producto_preferido_id integer,
    activo boolean DEFAULT true,
    notas text,
    created_at timestamp with time zone DEFAULT now(),
    CONSTRAINT clientes_frecuentes_perfil_check CHECK (((perfil)::text = ANY ((ARRAY['clase_media'::character varying, 'obrero'::character varying, 'sin_definir'::character varying])::text[])))
);


ALTER TABLE public.clientes_frecuentes OWNER TO neondb_owner;

--
-- Name: clientes_frecuentes_id_seq; Type: SEQUENCE; Schema: public; Owner: neondb_owner
--

CREATE SEQUENCE public.clientes_frecuentes_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.clientes_frecuentes_id_seq OWNER TO neondb_owner;

--
-- Name: clientes_frecuentes_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: neondb_owner
--

ALTER SEQUENCE public.clientes_frecuentes_id_seq OWNED BY public.clientes_frecuentes.id;


--
-- Name: deudas_diferidas; Type: TABLE; Schema: public; Owner: neondb_owner
--

CREATE TABLE public.deudas_diferidas (
    id integer NOT NULL,
    cliente_id integer NOT NULL,
    venta_id integer,
    monto integer NOT NULL,
    fecha_venta date NOT NULL,
    fecha_saldado date,
    estado character varying(20) DEFAULT 'pendiente'::character varying,
    notas text,
    CONSTRAINT deudas_diferidas_estado_check CHECK (((estado)::text = ANY ((ARRAY['pendiente'::character varying, 'saldado'::character varying])::text[])))
);


ALTER TABLE public.deudas_diferidas OWNER TO neondb_owner;

--
-- Name: deudas_diferidas_id_seq; Type: SEQUENCE; Schema: public; Owner: neondb_owner
--

CREATE SEQUENCE public.deudas_diferidas_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.deudas_diferidas_id_seq OWNER TO neondb_owner;

--
-- Name: deudas_diferidas_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: neondb_owner
--

ALTER SEQUENCE public.deudas_diferidas_id_seq OWNED BY public.deudas_diferidas.id;


--
-- Name: dispositivos; Type: TABLE; Schema: public; Owner: neondb_owner
--

CREATE TABLE public.dispositivos (
    id integer NOT NULL,
    uuid uuid DEFAULT public.uuid_generate_v4(),
    usuario_id integer NOT NULL,
    nombre character varying(100) NOT NULL,
    tipo character varying(20) NOT NULL,
    platform character varying(20),
    public_key text,
    ultimo_sync timestamp with time zone,
    confianza integer DEFAULT 0,
    revocado boolean DEFAULT false,
    created_at timestamp with time zone DEFAULT now(),
    CONSTRAINT dispositivos_tipo_check CHECK (((tipo)::text = ANY ((ARRAY['movil'::character varying, 'desktop'::character varying])::text[])))
);


ALTER TABLE public.dispositivos OWNER TO neondb_owner;

--
-- Name: dispositivos_id_seq; Type: SEQUENCE; Schema: public; Owner: neondb_owner
--

CREATE SEQUENCE public.dispositivos_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.dispositivos_id_seq OWNER TO neondb_owner;

--
-- Name: dispositivos_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: neondb_owner
--

ALTER SEQUENCE public.dispositivos_id_seq OWNED BY public.dispositivos.id;


--
-- Name: donaciones; Type: TABLE; Schema: public; Owner: neondb_owner
--

CREATE TABLE public.donaciones (
    id integer NOT NULL,
    fecha_recepcion date NOT NULL,
    fuente character varying(200),
    lugar_recepcion character varying(20) DEFAULT 'casa'::character varying,
    recibido_por_id integer NOT NULL,
    notas text,
    created_at timestamp with time zone DEFAULT now(),
    CONSTRAINT donaciones_lugar_recepcion_check CHECK (((lugar_recepcion)::text = ANY ((ARRAY['casa'::character varying, 'puesto'::character varying])::text[])))
);


ALTER TABLE public.donaciones OWNER TO neondb_owner;

--
-- Name: donaciones_id_seq; Type: SEQUENCE; Schema: public; Owner: neondb_owner
--

CREATE SEQUENCE public.donaciones_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.donaciones_id_seq OWNER TO neondb_owner;

--
-- Name: donaciones_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: neondb_owner
--

ALTER SEQUENCE public.donaciones_id_seq OWNED BY public.donaciones.id;


--
-- Name: etiquetas; Type: TABLE; Schema: public; Owner: neondb_owner
--

CREATE TABLE public.etiquetas (
    id integer NOT NULL,
    producto_id integer NOT NULL,
    tipo_codigo character varying(20) NOT NULL,
    codigo character varying(100) NOT NULL,
    formato_data text,
    impresa boolean DEFAULT false,
    fecha_impresion timestamp with time zone,
    estado character varying(20) DEFAULT 'activa'::character varying,
    ultima_lectura timestamp with time zone,
    ubicacion_actual character varying(100) DEFAULT 'bodega'::character varying,
    CONSTRAINT etiquetas_estado_check CHECK (((estado)::text = ANY ((ARRAY['activa'::character varying, 'perdida'::character varying, 'danada'::character varying, 'retirada'::character varying])::text[]))),
    CONSTRAINT etiquetas_tipo_codigo_check CHECK (((tipo_codigo)::text = ANY ((ARRAY['qr'::character varying, 'barcode'::character varying, 'rfid'::character varying])::text[])))
);


ALTER TABLE public.etiquetas OWNER TO neondb_owner;

--
-- Name: etiquetas_id_seq; Type: SEQUENCE; Schema: public; Owner: neondb_owner
--

CREATE SEQUENCE public.etiquetas_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.etiquetas_id_seq OWNER TO neondb_owner;

--
-- Name: etiquetas_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: neondb_owner
--

ALTER SEQUENCE public.etiquetas_id_seq OWNED BY public.etiquetas.id;


--
-- Name: eventos_feria; Type: TABLE; Schema: public; Owner: neondb_owner
--

CREATE TABLE public.eventos_feria (
    id integer NOT NULL,
    canal_venta_id integer NOT NULL,
    fecha date NOT NULL,
    lugar character varying(150),
    vendedor_principal_id integer NOT NULL,
    estado character varying(20) DEFAULT 'activo'::character varying,
    total_calculado integer DEFAULT 0,
    notas text,
    created_at timestamp with time zone DEFAULT now(),
    total_confirmado integer,
    diferencia integer,
    revisado_por_id integer,
    fecha_revision timestamp with time zone,
    fecha_cierre timestamp with time zone,
    CONSTRAINT eventos_feria_estado_check CHECK (((estado)::text = ANY ((ARRAY['planificado'::character varying, 'activo'::character varying, 'cerrado'::character varying])::text[])))
);


ALTER TABLE public.eventos_feria OWNER TO neondb_owner;

--
-- Name: eventos_feria_id_seq; Type: SEQUENCE; Schema: public; Owner: neondb_owner
--

CREATE SEQUENCE public.eventos_feria_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.eventos_feria_id_seq OWNER TO neondb_owner;

--
-- Name: eventos_feria_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: neondb_owner
--

ALTER SEQUENCE public.eventos_feria_id_seq OWNED BY public.eventos_feria.id;


--
-- Name: flujo_prenda; Type: TABLE; Schema: public; Owner: neondb_owner
--

CREATE TABLE public.flujo_prenda (
    id integer NOT NULL,
    producto_id integer NOT NULL,
    canal_origen character varying(20) NOT NULL,
    canal_destino character varying(20) NOT NULL,
    nivel_calidad_origen_id integer,
    nivel_calidad_destino_id integer,
    motivo text,
    evaluado_por_id integer,
    fecha_movimiento timestamp with time zone DEFAULT now(),
    notas text
);


ALTER TABLE public.flujo_prenda OWNER TO neondb_owner;

--
-- Name: flujo_prenda_id_seq; Type: SEQUENCE; Schema: public; Owner: neondb_owner
--

CREATE SEQUENCE public.flujo_prenda_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.flujo_prenda_id_seq OWNER TO neondb_owner;

--
-- Name: flujo_prenda_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: neondb_owner
--

ALTER SEQUENCE public.flujo_prenda_id_seq OWNED BY public.flujo_prenda.id;


--
-- Name: generos; Type: TABLE; Schema: public; Owner: neondb_owner
--

CREATE TABLE public.generos (
    id integer NOT NULL,
    codigo character varying(20) NOT NULL,
    nombre character varying(50) NOT NULL,
    activo boolean DEFAULT true
);


ALTER TABLE public.generos OWNER TO neondb_owner;

--
-- Name: generos_id_seq; Type: SEQUENCE; Schema: public; Owner: neondb_owner
--

CREATE SEQUENCE public.generos_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.generos_id_seq OWNER TO neondb_owner;

--
-- Name: generos_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: neondb_owner
--

ALTER SEQUENCE public.generos_id_seq OWNED BY public.generos.id;


--
-- Name: items_donacion; Type: TABLE; Schema: public; Owner: neondb_owner
--

CREATE TABLE public.items_donacion (
    id integer NOT NULL,
    donacion_id integer NOT NULL,
    descripcion character varying(200) NOT NULL,
    categoria_id integer,
    estado character varying(30) DEFAULT 'por_clasificar'::character varying,
    precio_min integer,
    precio_max integer,
    ubicacion_bodega character varying(100),
    clasificado_por_id integer,
    fecha_clasificacion date,
    vendido_en_evento_id integer,
    alerta_pendiente boolean DEFAULT false,
    notas text,
    created_at timestamp with time zone DEFAULT now(),
    CONSTRAINT items_donacion_estado_check CHECK (((estado)::text = ANY ((ARRAY['por_clasificar'::character varying, 'apto_venta'::character varying, 'descarte'::character varying, 'recuperar'::character varying, 'vendido'::character varying, 'vendido_sin_clasificar'::character varying])::text[])))
);


ALTER TABLE public.items_donacion OWNER TO neondb_owner;

--
-- Name: items_donacion_id_seq; Type: SEQUENCE; Schema: public; Owner: neondb_owner
--

CREATE SEQUENCE public.items_donacion_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.items_donacion_id_seq OWNER TO neondb_owner;

--
-- Name: items_donacion_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: neondb_owner
--

ALTER SEQUENCE public.items_donacion_id_seq OWNED BY public.items_donacion.id;


--
-- Name: journal_egresos; Type: TABLE; Schema: public; Owner: neondb_owner
--

CREATE TABLE public.journal_egresos (
    id integer NOT NULL,
    fecha date NOT NULL,
    usuario_id integer NOT NULL,
    dispositivo_id integer NOT NULL,
    tipo character varying(20) NOT NULL,
    proveedor character varying(150),
    producto_id integer,
    descripcion text,
    cantidad numeric(8,2),
    precio_unitario integer,
    total integer NOT NULL,
    forma_pago character varying(20) NOT NULL,
    notas text,
    sync_estado character varying(20) DEFAULT 'pendiente'::character varying,
    timestamp_local timestamp with time zone NOT NULL,
    timestamp_sync timestamp with time zone,
    created_at timestamp with time zone DEFAULT now(),
    CONSTRAINT journal_egresos_forma_pago_check CHECK (((forma_pago)::text = ANY ((ARRAY['efectivo'::character varying, 'transferencia'::character varying])::text[]))),
    CONSTRAINT journal_egresos_tipo_check CHECK (((tipo)::text = ANY ((ARRAY['compra_reventa'::character varying, 'compra_vecinos'::character varying, 'otro'::character varying])::text[])))
);


ALTER TABLE public.journal_egresos OWNER TO neondb_owner;

--
-- Name: journal_egresos_id_seq; Type: SEQUENCE; Schema: public; Owner: neondb_owner
--

CREATE SEQUENCE public.journal_egresos_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.journal_egresos_id_seq OWNER TO neondb_owner;

--
-- Name: journal_egresos_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: neondb_owner
--

ALTER SEQUENCE public.journal_egresos_id_seq OWNED BY public.journal_egresos.id;


--
-- Name: journal_insumos; Type: TABLE; Schema: public; Owner: neondb_owner
--

CREATE TABLE public.journal_insumos (
    id integer NOT NULL,
    fecha date NOT NULL,
    usuario_id integer NOT NULL,
    dispositivo_id integer NOT NULL,
    tipo character varying(30) NOT NULL,
    descripcion text NOT NULL,
    monto integer NOT NULL,
    forma_pago character varying(20) NOT NULL,
    notas text,
    sync_estado character varying(20) DEFAULT 'pendiente'::character varying,
    timestamp_local timestamp with time zone NOT NULL,
    timestamp_sync timestamp with time zone,
    created_at timestamp with time zone DEFAULT now(),
    CONSTRAINT journal_insumos_forma_pago_check CHECK (((forma_pago)::text = ANY ((ARRAY['efectivo'::character varying, 'transferencia'::character varying])::text[]))),
    CONSTRAINT journal_insumos_tipo_check CHECK (((tipo)::text = ANY ((ARRAY['alimento_gallinas'::character varying, 'reposicion_gallinas'::character varying, 'infraestructura'::character varying, 'plantines_semillas'::character varying, 'otro'::character varying])::text[])))
);


ALTER TABLE public.journal_insumos OWNER TO neondb_owner;

--
-- Name: journal_insumos_id_seq; Type: SEQUENCE; Schema: public; Owner: neondb_owner
--

CREATE SEQUENCE public.journal_insumos_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.journal_insumos_id_seq OWNER TO neondb_owner;

--
-- Name: journal_insumos_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: neondb_owner
--

ALTER SEQUENCE public.journal_insumos_id_seq OWNED BY public.journal_insumos.id;


--
-- Name: journal_ventas; Type: TABLE; Schema: public; Owner: neondb_owner
--

CREATE TABLE public.journal_ventas (
    id integer NOT NULL,
    uuid uuid DEFAULT public.uuid_generate_v4(),
    evento_feria_id integer NOT NULL,
    usuario_id integer NOT NULL,
    dispositivo_id integer NOT NULL,
    timestamp_local timestamp with time zone NOT NULL,
    timestamp_sync timestamp with time zone,
    perfil_cliente character varying(20) DEFAULT 'sin_definir'::character varying,
    producto_ancla_id integer,
    forma_pago character varying(20) NOT NULL,
    estado_pago character varying(20) DEFAULT 'pagado'::character varying,
    cliente_frecuente_id integer,
    venta_directa_sin_bodega boolean DEFAULT false,
    garantia_devolucion boolean DEFAULT false,
    total_venta integer DEFAULT 0 NOT NULL,
    sync_estado character varying(20) DEFAULT 'pendiente'::character varying,
    notas text,
    created_at timestamp with time zone DEFAULT now(),
    precio_standard_total integer,
    precio_final_total integer DEFAULT 0 NOT NULL,
    diferencia_rebaja integer,
    porcentaje_rebaja numeric(5,2),
    tipo_rebaja character varying(30),
    motivo_rebaja text,
    aprobado_por_id integer,
    CONSTRAINT journal_ventas_estado_pago_check CHECK (((estado_pago)::text = ANY ((ARRAY['pagado'::character varying, 'mora'::character varying, 'pendiente'::character varying, 'trueque'::character varying])::text[]))),
    CONSTRAINT journal_ventas_forma_pago_check CHECK (((forma_pago)::text = ANY ((ARRAY['efectivo'::character varying, 'transferencia'::character varying, 'diferido'::character varying, 'debito'::character varying, 'credito'::character varying, 'trueque'::character varying])::text[]))),
    CONSTRAINT journal_ventas_sync_estado_check CHECK (((sync_estado)::text = ANY ((ARRAY['pendiente'::character varying, 'sincronizado'::character varying, 'conflicto'::character varying])::text[]))),
    CONSTRAINT journal_ventas_tipo_rebaja_check CHECK (((tipo_rebaja)::text = ANY ((ARRAY['ninguna'::character varying, 'rebaja_cliente_frecuente'::character varying, 'compra_masiva'::character varying, 'prenda_especial'::character varying, 'promocion_temporal'::character varying, 'error_correccion'::character varying, 'mora_negociada'::character varying, 'trueque_valor_menor'::character varying, 'otro'::character varying])::text[])))
);


ALTER TABLE public.journal_ventas OWNER TO neondb_owner;

--
-- Name: journal_ventas_id_seq; Type: SEQUENCE; Schema: public; Owner: neondb_owner
--

CREATE SEQUENCE public.journal_ventas_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.journal_ventas_id_seq OWNER TO neondb_owner;

--
-- Name: journal_ventas_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: neondb_owner
--

ALTER SEQUENCE public.journal_ventas_id_seq OWNED BY public.journal_ventas.id;


--
-- Name: lineas_venta; Type: TABLE; Schema: public; Owner: neondb_owner
--

CREATE TABLE public.lineas_venta (
    id integer NOT NULL,
    venta_id integer NOT NULL,
    producto_id integer,
    item_donacion_id integer,
    cantidad numeric(8,2) DEFAULT 1.00 NOT NULL,
    precio_unitario_final integer CONSTRAINT lineas_venta_precio_unitario_not_null NOT NULL,
    subtotal integer NOT NULL,
    notas text,
    precio_unitario_standard integer
);


ALTER TABLE public.lineas_venta OWNER TO neondb_owner;

--
-- Name: lineas_venta_id_seq; Type: SEQUENCE; Schema: public; Owner: neondb_owner
--

CREATE SEQUENCE public.lineas_venta_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.lineas_venta_id_seq OWNER TO neondb_owner;

--
-- Name: lineas_venta_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: neondb_owner
--

ALTER SEQUENCE public.lineas_venta_id_seq OWNED BY public.lineas_venta.id;


--
-- Name: niveles_calidad; Type: TABLE; Schema: public; Owner: neondb_owner
--

CREATE TABLE public.niveles_calidad (
    id integer NOT NULL,
    codigo character varying(30) NOT NULL,
    nombre character varying(100) NOT NULL,
    canal_asignado character varying(20) NOT NULL,
    descripcion text,
    criterios text,
    activo boolean DEFAULT true,
    CONSTRAINT niveles_calidad_canal_asignado_check CHECK (((canal_asignado)::text = ANY ((ARRAY['online'::character varying, 'feria'::character varying, 'retazo'::character varying])::text[])))
);


ALTER TABLE public.niveles_calidad OWNER TO neondb_owner;

--
-- Name: niveles_calidad_id_seq; Type: SEQUENCE; Schema: public; Owner: neondb_owner
--

CREATE SEQUENCE public.niveles_calidad_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.niveles_calidad_id_seq OWNER TO neondb_owner;

--
-- Name: niveles_calidad_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: neondb_owner
--

ALTER SEQUENCE public.niveles_calidad_id_seq OWNED BY public.niveles_calidad.id;


--
-- Name: ofertas_cruzadas; Type: TABLE; Schema: public; Owner: neondb_owner
--

CREATE TABLE public.ofertas_cruzadas (
    id integer NOT NULL,
    proyecto_origen character varying(50) NOT NULL,
    proyecto_destino character varying(50) NOT NULL,
    tipo_oferta character varying(30) NOT NULL,
    condicion_trigger text,
    beneficio jsonb,
    vigencia_desde date NOT NULL,
    vigencia_hasta date,
    activa boolean DEFAULT true,
    limite_usos integer,
    usos_actuales integer DEFAULT 0,
    CONSTRAINT ofertas_cruzadas_tipo_oferta_check CHECK (((tipo_oferta)::text = ANY ((ARRAY['descuento_porcentaje'::character varying, 'descuento_fijo'::character varying, 'producto_gratis'::character varying, 'trueque'::character varying, 'acceso_prioritario'::character varying, 'experiencia'::character varying])::text[])))
);


ALTER TABLE public.ofertas_cruzadas OWNER TO neondb_owner;

--
-- Name: ofertas_cruzadas_id_seq; Type: SEQUENCE; Schema: public; Owner: neondb_owner
--

CREATE SEQUENCE public.ofertas_cruzadas_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.ofertas_cruzadas_id_seq OWNER TO neondb_owner;

--
-- Name: ofertas_cruzadas_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: neondb_owner
--

ALTER SEQUENCE public.ofertas_cruzadas_id_seq OWNED BY public.ofertas_cruzadas.id;


--
-- Name: precios_standard; Type: TABLE; Schema: public; Owner: neondb_owner
--

CREATE TABLE public.precios_standard (
    id integer NOT NULL,
    producto_id integer NOT NULL,
    canal character varying(20) NOT NULL,
    precio_standard integer NOT NULL,
    moneda character varying(3) DEFAULT 'CLP'::character varying,
    vigente_desde date NOT NULL,
    vigente_hasta date,
    CONSTRAINT precios_standard_canal_check CHECK (((canal)::text = ANY ((ARRAY['online'::character varying, 'feria'::character varying, 'retazo'::character varying])::text[])))
);


ALTER TABLE public.precios_standard OWNER TO neondb_owner;

--
-- Name: precios_standard_id_seq; Type: SEQUENCE; Schema: public; Owner: neondb_owner
--

CREATE SEQUENCE public.precios_standard_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.precios_standard_id_seq OWNER TO neondb_owner;

--
-- Name: precios_standard_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: neondb_owner
--

ALTER SEQUENCE public.precios_standard_id_seq OWNED BY public.precios_standard.id;


--
-- Name: productos; Type: TABLE; Schema: public; Owner: neondb_owner
--

CREATE TABLE public.productos (
    id integer NOT NULL,
    uuid uuid DEFAULT public.uuid_generate_v4(),
    nombre character varying(150) NOT NULL,
    categoria_feriaapp_id integer CONSTRAINT productos_categoria_id_not_null NOT NULL,
    subcategoria_feriaapp_id integer,
    unidad_medida character varying(30) NOT NULL,
    precio_fijo integer,
    precio_min integer,
    precio_max integer,
    tiene_rango boolean DEFAULT false,
    genero character varying(20),
    segmento_edad character varying(20)[] DEFAULT '{}'::character varying[],
    canal_default character varying(20) DEFAULT 'feria'::character varying,
    condicion character varying(30),
    estado character varying(20) DEFAULT 'disponible'::character varying,
    etiqueta_id character varying(50),
    fotos jsonb DEFAULT '[]'::jsonb,
    activo boolean DEFAULT true,
    notas text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    codigo_barras character varying(50),
    categoria_revistete_id integer,
    subcategoria_revistete_id integer,
    genero_id integer,
    segmento_edad_id integer,
    talla character varying(20),
    talla_numerica integer,
    medidas jsonb,
    precio_online integer,
    precio_feria integer,
    precio_standard integer,
    precio_final integer,
    nivel_calidad_id integer,
    temporada_id integer,
    temporadas_en_inventario integer DEFAULT 0,
    descripcion_defectos text,
    marca character varying(100),
    evaluado_por_id integer,
    fecha_evaluacion timestamp with time zone,
    CONSTRAINT productos_condicion_check CHECK (((condicion)::text = ANY ((ARRAY['como_nueva_marca'::character varying, 'como_nueva_boutique'::character varying, 'intervenida'::character varying, 'primera_seleccion'::character varying, 'sin_marca'::character varying, 'donacion'::character varying, 'digna_portar'::character varying, 'retazo'::character varying])::text[]))),
    CONSTRAINT productos_estado_check CHECK (((estado)::text = ANY ((ARRAY['disponible'::character varying, 'reservado'::character varying, 'vendido'::character varying, 'retazo'::character varying, 'donado'::character varying, 'en_evaluacion'::character varying])::text[]))),
    CONSTRAINT productos_genero_check CHECK (((genero)::text = ANY ((ARRAY['hombre'::character varying, 'mujer'::character varying, 'unisex'::character varying, 'niño'::character varying, 'niña'::character varying, 'bebe'::character varying])::text[])))
);


ALTER TABLE public.productos OWNER TO neondb_owner;

--
-- Name: productos_id_seq; Type: SEQUENCE; Schema: public; Owner: neondb_owner
--

CREATE SEQUENCE public.productos_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.productos_id_seq OWNER TO neondb_owner;

--
-- Name: productos_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: neondb_owner
--

ALTER SEQUENCE public.productos_id_seq OWNED BY public.productos.id;


--
-- Name: reclasificacion_log; Type: TABLE; Schema: public; Owner: neondb_owner
--

CREATE TABLE public.reclasificacion_log (
    id integer NOT NULL,
    venta_id integer,
    campo_afectado character varying(50) NOT NULL,
    valor_anterior text,
    valor_nuevo text,
    motivo text,
    nota_original text,
    operador character varying(100),
    confirmado boolean DEFAULT false,
    fecha_cambio timestamp with time zone DEFAULT now()
);


ALTER TABLE public.reclasificacion_log OWNER TO neondb_owner;

--
-- Name: reclasificacion_log_id_seq; Type: SEQUENCE; Schema: public; Owner: neondb_owner
--

CREATE SEQUENCE public.reclasificacion_log_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.reclasificacion_log_id_seq OWNER TO neondb_owner;

--
-- Name: reclasificacion_log_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: neondb_owner
--

ALTER SEQUENCE public.reclasificacion_log_id_seq OWNED BY public.reclasificacion_log.id;


--
-- Name: refresh_tokens; Type: TABLE; Schema: public; Owner: neondb_owner
--

CREATE TABLE public.refresh_tokens (
    id integer NOT NULL,
    dispositivo_id integer NOT NULL,
    token_hash character varying(255) NOT NULL,
    expira_en timestamp with time zone NOT NULL,
    usado_en timestamp with time zone,
    revocado boolean DEFAULT false,
    ip_origen inet,
    user_agent text,
    created_at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.refresh_tokens OWNER TO neondb_owner;

--
-- Name: refresh_tokens_id_seq; Type: SEQUENCE; Schema: public; Owner: neondb_owner
--

CREATE SEQUENCE public.refresh_tokens_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.refresh_tokens_id_seq OWNER TO neondb_owner;

--
-- Name: refresh_tokens_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: neondb_owner
--

ALTER SEQUENCE public.refresh_tokens_id_seq OWNED BY public.refresh_tokens.id;


--
-- Name: segmentos_edad; Type: TABLE; Schema: public; Owner: neondb_owner
--

CREATE TABLE public.segmentos_edad (
    id integer NOT NULL,
    codigo character varying(20) NOT NULL,
    nombre character varying(50) NOT NULL,
    rango_anios character varying(30),
    activo boolean DEFAULT true
);


ALTER TABLE public.segmentos_edad OWNER TO neondb_owner;

--
-- Name: segmentos_edad_id_seq; Type: SEQUENCE; Schema: public; Owner: neondb_owner
--

CREATE SEQUENCE public.segmentos_edad_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.segmentos_edad_id_seq OWNER TO neondb_owner;

--
-- Name: segmentos_edad_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: neondb_owner
--

ALTER SEQUENCE public.segmentos_edad_id_seq OWNED BY public.segmentos_edad.id;


--
-- Name: subcategorias_producto; Type: TABLE; Schema: public; Owner: neondb_owner
--

CREATE TABLE public.subcategorias_producto (
    id integer NOT NULL,
    categoria_id integer NOT NULL,
    nombre character varying(100) NOT NULL,
    activo boolean DEFAULT true
);


ALTER TABLE public.subcategorias_producto OWNER TO neondb_owner;

--
-- Name: subcategorias_producto_id_seq; Type: SEQUENCE; Schema: public; Owner: neondb_owner
--

CREATE SEQUENCE public.subcategorias_producto_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.subcategorias_producto_id_seq OWNER TO neondb_owner;

--
-- Name: subcategorias_producto_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: neondb_owner
--

ALTER SEQUENCE public.subcategorias_producto_id_seq OWNED BY public.subcategorias_producto.id;


--
-- Name: subcategorias_ropa; Type: TABLE; Schema: public; Owner: neondb_owner
--

CREATE TABLE public.subcategorias_ropa (
    id integer NOT NULL,
    categoria_id integer NOT NULL,
    codigo character varying(30) NOT NULL,
    nombre character varying(100) NOT NULL,
    especificaciones text,
    activo boolean DEFAULT true
);


ALTER TABLE public.subcategorias_ropa OWNER TO neondb_owner;

--
-- Name: subcategorias_ropa_id_seq; Type: SEQUENCE; Schema: public; Owner: neondb_owner
--

CREATE SEQUENCE public.subcategorias_ropa_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.subcategorias_ropa_id_seq OWNER TO neondb_owner;

--
-- Name: subcategorias_ropa_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: neondb_owner
--

ALTER SEQUENCE public.subcategorias_ropa_id_seq OWNED BY public.subcategorias_ropa.id;


--
-- Name: sync_log; Type: TABLE; Schema: public; Owner: neondb_owner
--

CREATE TABLE public.sync_log (
    id integer NOT NULL,
    dispositivo_id integer NOT NULL,
    usuario_id integer NOT NULL,
    tabla_afectada character varying(50) NOT NULL,
    registro_id integer NOT NULL,
    operacion character varying(20) NOT NULL,
    timestamp_local timestamp with time zone NOT NULL,
    timestamp_servidor timestamp with time zone DEFAULT now(),
    estado character varying(20) DEFAULT 'ok'::character varying,
    detalle text,
    CONSTRAINT sync_log_estado_check CHECK (((estado)::text = ANY ((ARRAY['ok'::character varying, 'duplicado'::character varying, 'conflicto'::character varying])::text[]))),
    CONSTRAINT sync_log_operacion_check CHECK (((operacion)::text = ANY ((ARRAY['insert'::character varying, 'update'::character varying, 'delete'::character varying])::text[])))
);


ALTER TABLE public.sync_log OWNER TO neondb_owner;

--
-- Name: sync_log_id_seq; Type: SEQUENCE; Schema: public; Owner: neondb_owner
--

CREATE SEQUENCE public.sync_log_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.sync_log_id_seq OWNER TO neondb_owner;

--
-- Name: sync_log_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: neondb_owner
--

ALTER SEQUENCE public.sync_log_id_seq OWNED BY public.sync_log.id;


--
-- Name: temporadas; Type: TABLE; Schema: public; Owner: neondb_owner
--

CREATE TABLE public.temporadas (
    id integer NOT NULL,
    codigo character varying(20) NOT NULL,
    nombre character varying(50) NOT NULL,
    meses_inicio integer,
    meses_fin integer,
    activo boolean DEFAULT true
);


ALTER TABLE public.temporadas OWNER TO neondb_owner;

--
-- Name: temporadas_id_seq; Type: SEQUENCE; Schema: public; Owner: neondb_owner
--

CREATE SEQUENCE public.temporadas_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.temporadas_id_seq OWNER TO neondb_owner;

--
-- Name: temporadas_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: neondb_owner
--

ALTER SEQUENCE public.temporadas_id_seq OWNED BY public.temporadas.id;


--
-- Name: usuarios; Type: TABLE; Schema: public; Owner: neondb_owner
--

CREATE TABLE public.usuarios (
    id integer NOT NULL,
    uuid uuid DEFAULT public.uuid_generate_v4(),
    nombre character varying(100) NOT NULL,
    rol character varying(20) NOT NULL,
    password_hash character varying(255) NOT NULL,
    activo boolean DEFAULT true,
    created_at timestamp with time zone DEFAULT now(),
    CONSTRAINT usuarios_rol_check CHECK (((rol)::text = ANY ((ARRAY['propietario'::character varying, 'esposa'::character varying, 'hija_mayor'::character varying, 'hija_menor'::character varying, 'externo'::character varying])::text[])))
);


ALTER TABLE public.usuarios OWNER TO neondb_owner;

--
-- Name: usuarios_id_seq; Type: SEQUENCE; Schema: public; Owner: neondb_owner
--

CREATE SEQUENCE public.usuarios_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.usuarios_id_seq OWNER TO neondb_owner;

--
-- Name: usuarios_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: neondb_owner
--

ALTER SEQUENCE public.usuarios_id_seq OWNED BY public.usuarios.id;


--
-- Name: v_productos_disponibles; Type: VIEW; Schema: public; Owner: neondb_owner
--

CREATE VIEW public.v_productos_disponibles AS
 SELECT p.id,
    p.uuid,
    p.nombre,
    p.etiqueta_id,
    p.codigo_barras,
    p.marca,
    p.talla,
    p.condicion,
    p.estado,
    p.precio_online,
    p.precio_feria,
    p.precio_standard,
    p.precio_final,
    p.temporadas_en_inventario,
    p.descripcion_defectos,
    p.fotos,
    p.created_at,
    p.updated_at,
    g.nombre AS genero,
    se.nombre AS segmento_edad,
    cr.nombre AS categoria_revistete,
    sr.nombre AS subcategoria_revistete,
    cf.nombre AS categoria_feriaapp,
    sf.nombre AS subcategoria_feriaapp,
    nc.nombre AS nivel_calidad,
    nc.canal_asignado AS canal_recomendado,
    t.nombre AS temporada
   FROM ((((((((public.productos p
     LEFT JOIN public.generos g ON ((p.genero_id = g.id)))
     LEFT JOIN public.segmentos_edad se ON ((p.segmento_edad_id = se.id)))
     LEFT JOIN public.categorias_ropa cr ON ((p.categoria_revistete_id = cr.id)))
     LEFT JOIN public.subcategorias_ropa sr ON ((p.subcategoria_revistete_id = sr.id)))
     LEFT JOIN public.categorias_producto cf ON ((p.categoria_feriaapp_id = cf.id)))
     LEFT JOIN public.subcategorias_producto sf ON ((p.subcategoria_feriaapp_id = sf.id)))
     LEFT JOIN public.niveles_calidad nc ON ((p.nivel_calidad_id = nc.id)))
     LEFT JOIN public.temporadas t ON ((p.temporada_id = t.id)))
  WHERE ((p.activo = true) AND ((p.estado)::text = ANY ((ARRAY['disponible'::character varying, 'en_evaluacion'::character varying])::text[])));


ALTER VIEW public.v_productos_disponibles OWNER TO neondb_owner;

--
-- Name: v_rebajas_por_evento; Type: VIEW; Schema: public; Owner: neondb_owner
--

CREATE VIEW public.v_rebajas_por_evento AS
 SELECT ef.id AS evento_id,
    ef.fecha,
    ef.lugar,
    ef.estado,
    count(jv.id) AS total_ventas,
    sum(jv.precio_standard_total) AS total_standard,
    sum(jv.precio_final_total) AS total_final,
    sum(COALESCE(jv.diferencia_rebaja, 0)) AS total_rebajas,
    round(avg(COALESCE(jv.porcentaje_rebaja, (0)::numeric)), 2) AS rebaja_promedio_pct
   FROM (public.eventos_feria ef
     LEFT JOIN public.journal_ventas jv ON ((ef.id = jv.evento_feria_id)))
  GROUP BY ef.id, ef.fecha, ef.lugar, ef.estado;


ALTER VIEW public.v_rebajas_por_evento OWNER TO neondb_owner;

--
-- Name: venta_rebajas; Type: TABLE; Schema: public; Owner: neondb_owner
--

CREATE TABLE public.venta_rebajas (
    id integer NOT NULL,
    venta_id integer NOT NULL,
    linea_venta_id integer,
    precio_standard integer NOT NULL,
    precio_final integer NOT NULL,
    diferencia integer GENERATED ALWAYS AS ((precio_final - precio_standard)) STORED,
    tipo_rebaja character varying(30) DEFAULT 'ninguna'::character varying,
    porcentaje_rebaja numeric(5,2) GENERATED ALWAYS AS (
CASE
    WHEN (precio_standard > 0) THEN ((((precio_standard - precio_final))::numeric / (precio_standard)::numeric) * (100)::numeric)
    ELSE (0)::numeric
END) STORED,
    nota_rebaja text,
    aprobado_por_id integer,
    fecha_registro timestamp with time zone DEFAULT now(),
    CONSTRAINT venta_rebajas_tipo_rebaja_check CHECK (((tipo_rebaja)::text = ANY ((ARRAY['ninguna'::character varying, 'rebaja_cliente_frecuente'::character varying, 'compra_masiva'::character varying, 'prenda_especial'::character varying, 'promocion_temporal'::character varying, 'error_correccion'::character varying, 'mora_negociada'::character varying, 'trueque_valor_menor'::character varying, 'otro'::character varying])::text[])))
);


ALTER TABLE public.venta_rebajas OWNER TO neondb_owner;

--
-- Name: venta_rebajas_id_seq; Type: SEQUENCE; Schema: public; Owner: neondb_owner
--

CREATE SEQUENCE public.venta_rebajas_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.venta_rebajas_id_seq OWNER TO neondb_owner;

--
-- Name: venta_rebajas_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: neondb_owner
--

ALTER SEQUENCE public.venta_rebajas_id_seq OWNED BY public.venta_rebajas.id;


--
-- Name: canales_venta id; Type: DEFAULT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.canales_venta ALTER COLUMN id SET DEFAULT nextval('public.canales_venta_id_seq'::regclass);


--
-- Name: categorias_producto id; Type: DEFAULT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.categorias_producto ALTER COLUMN id SET DEFAULT nextval('public.categorias_producto_id_seq'::regclass);


--
-- Name: categorias_ropa id; Type: DEFAULT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.categorias_ropa ALTER COLUMN id SET DEFAULT nextval('public.categorias_ropa_id_seq'::regclass);


--
-- Name: clientes_frecuentes id; Type: DEFAULT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.clientes_frecuentes ALTER COLUMN id SET DEFAULT nextval('public.clientes_frecuentes_id_seq'::regclass);


--
-- Name: deudas_diferidas id; Type: DEFAULT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.deudas_diferidas ALTER COLUMN id SET DEFAULT nextval('public.deudas_diferidas_id_seq'::regclass);


--
-- Name: dispositivos id; Type: DEFAULT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.dispositivos ALTER COLUMN id SET DEFAULT nextval('public.dispositivos_id_seq'::regclass);


--
-- Name: donaciones id; Type: DEFAULT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.donaciones ALTER COLUMN id SET DEFAULT nextval('public.donaciones_id_seq'::regclass);


--
-- Name: etiquetas id; Type: DEFAULT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.etiquetas ALTER COLUMN id SET DEFAULT nextval('public.etiquetas_id_seq'::regclass);


--
-- Name: eventos_feria id; Type: DEFAULT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.eventos_feria ALTER COLUMN id SET DEFAULT nextval('public.eventos_feria_id_seq'::regclass);


--
-- Name: flujo_prenda id; Type: DEFAULT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.flujo_prenda ALTER COLUMN id SET DEFAULT nextval('public.flujo_prenda_id_seq'::regclass);


--
-- Name: generos id; Type: DEFAULT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.generos ALTER COLUMN id SET DEFAULT nextval('public.generos_id_seq'::regclass);


--
-- Name: items_donacion id; Type: DEFAULT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.items_donacion ALTER COLUMN id SET DEFAULT nextval('public.items_donacion_id_seq'::regclass);


--
-- Name: journal_egresos id; Type: DEFAULT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.journal_egresos ALTER COLUMN id SET DEFAULT nextval('public.journal_egresos_id_seq'::regclass);


--
-- Name: journal_insumos id; Type: DEFAULT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.journal_insumos ALTER COLUMN id SET DEFAULT nextval('public.journal_insumos_id_seq'::regclass);


--
-- Name: journal_ventas id; Type: DEFAULT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.journal_ventas ALTER COLUMN id SET DEFAULT nextval('public.journal_ventas_id_seq'::regclass);


--
-- Name: lineas_venta id; Type: DEFAULT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.lineas_venta ALTER COLUMN id SET DEFAULT nextval('public.lineas_venta_id_seq'::regclass);


--
-- Name: niveles_calidad id; Type: DEFAULT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.niveles_calidad ALTER COLUMN id SET DEFAULT nextval('public.niveles_calidad_id_seq'::regclass);


--
-- Name: ofertas_cruzadas id; Type: DEFAULT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.ofertas_cruzadas ALTER COLUMN id SET DEFAULT nextval('public.ofertas_cruzadas_id_seq'::regclass);


--
-- Name: precios_standard id; Type: DEFAULT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.precios_standard ALTER COLUMN id SET DEFAULT nextval('public.precios_standard_id_seq'::regclass);


--
-- Name: productos id; Type: DEFAULT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.productos ALTER COLUMN id SET DEFAULT nextval('public.productos_id_seq'::regclass);


--
-- Name: reclasificacion_log id; Type: DEFAULT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.reclasificacion_log ALTER COLUMN id SET DEFAULT nextval('public.reclasificacion_log_id_seq'::regclass);


--
-- Name: refresh_tokens id; Type: DEFAULT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.refresh_tokens ALTER COLUMN id SET DEFAULT nextval('public.refresh_tokens_id_seq'::regclass);


--
-- Name: segmentos_edad id; Type: DEFAULT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.segmentos_edad ALTER COLUMN id SET DEFAULT nextval('public.segmentos_edad_id_seq'::regclass);


--
-- Name: subcategorias_producto id; Type: DEFAULT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.subcategorias_producto ALTER COLUMN id SET DEFAULT nextval('public.subcategorias_producto_id_seq'::regclass);


--
-- Name: subcategorias_ropa id; Type: DEFAULT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.subcategorias_ropa ALTER COLUMN id SET DEFAULT nextval('public.subcategorias_ropa_id_seq'::regclass);


--
-- Name: sync_log id; Type: DEFAULT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.sync_log ALTER COLUMN id SET DEFAULT nextval('public.sync_log_id_seq'::regclass);


--
-- Name: temporadas id; Type: DEFAULT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.temporadas ALTER COLUMN id SET DEFAULT nextval('public.temporadas_id_seq'::regclass);


--
-- Name: usuarios id; Type: DEFAULT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.usuarios ALTER COLUMN id SET DEFAULT nextval('public.usuarios_id_seq'::regclass);


--
-- Name: venta_rebajas id; Type: DEFAULT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.venta_rebajas ALTER COLUMN id SET DEFAULT nextval('public.venta_rebajas_id_seq'::regclass);


--
-- Name: canales_venta canales_venta_pkey; Type: CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.canales_venta
    ADD CONSTRAINT canales_venta_pkey PRIMARY KEY (id);


--
-- Name: categoria_canal categoria_canal_pkey; Type: CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.categoria_canal
    ADD CONSTRAINT categoria_canal_pkey PRIMARY KEY (categoria_id, canal_id);


--
-- Name: categorias_producto categorias_producto_pkey; Type: CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.categorias_producto
    ADD CONSTRAINT categorias_producto_pkey PRIMARY KEY (id);


--
-- Name: categorias_ropa categorias_ropa_codigo_key; Type: CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.categorias_ropa
    ADD CONSTRAINT categorias_ropa_codigo_key UNIQUE (codigo);


--
-- Name: categorias_ropa categorias_ropa_pkey; Type: CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.categorias_ropa
    ADD CONSTRAINT categorias_ropa_pkey PRIMARY KEY (id);


--
-- Name: clientes_frecuentes clientes_frecuentes_pkey; Type: CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.clientes_frecuentes
    ADD CONSTRAINT clientes_frecuentes_pkey PRIMARY KEY (id);


--
-- Name: deudas_diferidas deudas_diferidas_pkey; Type: CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.deudas_diferidas
    ADD CONSTRAINT deudas_diferidas_pkey PRIMARY KEY (id);


--
-- Name: dispositivos dispositivos_pkey; Type: CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.dispositivos
    ADD CONSTRAINT dispositivos_pkey PRIMARY KEY (id);


--
-- Name: dispositivos dispositivos_uuid_key; Type: CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.dispositivos
    ADD CONSTRAINT dispositivos_uuid_key UNIQUE (uuid);


--
-- Name: donaciones donaciones_pkey; Type: CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.donaciones
    ADD CONSTRAINT donaciones_pkey PRIMARY KEY (id);


--
-- Name: etiquetas etiquetas_codigo_key; Type: CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.etiquetas
    ADD CONSTRAINT etiquetas_codigo_key UNIQUE (codigo);


--
-- Name: etiquetas etiquetas_pkey; Type: CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.etiquetas
    ADD CONSTRAINT etiquetas_pkey PRIMARY KEY (id);


--
-- Name: eventos_feria eventos_feria_pkey; Type: CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.eventos_feria
    ADD CONSTRAINT eventos_feria_pkey PRIMARY KEY (id);


--
-- Name: flujo_prenda flujo_prenda_pkey; Type: CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.flujo_prenda
    ADD CONSTRAINT flujo_prenda_pkey PRIMARY KEY (id);


--
-- Name: generos generos_codigo_key; Type: CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.generos
    ADD CONSTRAINT generos_codigo_key UNIQUE (codigo);


--
-- Name: generos generos_pkey; Type: CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.generos
    ADD CONSTRAINT generos_pkey PRIMARY KEY (id);


--
-- Name: items_donacion items_donacion_pkey; Type: CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.items_donacion
    ADD CONSTRAINT items_donacion_pkey PRIMARY KEY (id);


--
-- Name: journal_egresos journal_egresos_pkey; Type: CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.journal_egresos
    ADD CONSTRAINT journal_egresos_pkey PRIMARY KEY (id);


--
-- Name: journal_insumos journal_insumos_pkey; Type: CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.journal_insumos
    ADD CONSTRAINT journal_insumos_pkey PRIMARY KEY (id);


--
-- Name: journal_ventas journal_ventas_pkey; Type: CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.journal_ventas
    ADD CONSTRAINT journal_ventas_pkey PRIMARY KEY (id);


--
-- Name: journal_ventas journal_ventas_uuid_key; Type: CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.journal_ventas
    ADD CONSTRAINT journal_ventas_uuid_key UNIQUE (uuid);


--
-- Name: lineas_venta lineas_venta_pkey; Type: CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.lineas_venta
    ADD CONSTRAINT lineas_venta_pkey PRIMARY KEY (id);


--
-- Name: niveles_calidad niveles_calidad_codigo_key; Type: CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.niveles_calidad
    ADD CONSTRAINT niveles_calidad_codigo_key UNIQUE (codigo);


--
-- Name: niveles_calidad niveles_calidad_pkey; Type: CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.niveles_calidad
    ADD CONSTRAINT niveles_calidad_pkey PRIMARY KEY (id);


--
-- Name: ofertas_cruzadas ofertas_cruzadas_pkey; Type: CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.ofertas_cruzadas
    ADD CONSTRAINT ofertas_cruzadas_pkey PRIMARY KEY (id);


--
-- Name: precios_standard precios_standard_pkey; Type: CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.precios_standard
    ADD CONSTRAINT precios_standard_pkey PRIMARY KEY (id);


--
-- Name: precios_standard precios_standard_producto_id_canal_vigente_desde_key; Type: CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.precios_standard
    ADD CONSTRAINT precios_standard_producto_id_canal_vigente_desde_key UNIQUE (producto_id, canal, vigente_desde);


--
-- Name: productos productos_codigo_barras_key; Type: CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.productos
    ADD CONSTRAINT productos_codigo_barras_key UNIQUE (codigo_barras);


--
-- Name: productos productos_etiqueta_id_key; Type: CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.productos
    ADD CONSTRAINT productos_etiqueta_id_key UNIQUE (etiqueta_id);


--
-- Name: productos productos_pkey; Type: CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.productos
    ADD CONSTRAINT productos_pkey PRIMARY KEY (id);


--
-- Name: productos productos_uuid_key; Type: CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.productos
    ADD CONSTRAINT productos_uuid_key UNIQUE (uuid);


--
-- Name: reclasificacion_log reclasificacion_log_pkey; Type: CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.reclasificacion_log
    ADD CONSTRAINT reclasificacion_log_pkey PRIMARY KEY (id);


--
-- Name: refresh_tokens refresh_tokens_pkey; Type: CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.refresh_tokens
    ADD CONSTRAINT refresh_tokens_pkey PRIMARY KEY (id);


--
-- Name: segmentos_edad segmentos_edad_codigo_key; Type: CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.segmentos_edad
    ADD CONSTRAINT segmentos_edad_codigo_key UNIQUE (codigo);


--
-- Name: segmentos_edad segmentos_edad_pkey; Type: CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.segmentos_edad
    ADD CONSTRAINT segmentos_edad_pkey PRIMARY KEY (id);


--
-- Name: subcategorias_producto subcategorias_producto_pkey; Type: CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.subcategorias_producto
    ADD CONSTRAINT subcategorias_producto_pkey PRIMARY KEY (id);


--
-- Name: subcategorias_ropa subcategorias_ropa_codigo_key; Type: CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.subcategorias_ropa
    ADD CONSTRAINT subcategorias_ropa_codigo_key UNIQUE (codigo);


--
-- Name: subcategorias_ropa subcategorias_ropa_pkey; Type: CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.subcategorias_ropa
    ADD CONSTRAINT subcategorias_ropa_pkey PRIMARY KEY (id);


--
-- Name: sync_log sync_log_pkey; Type: CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.sync_log
    ADD CONSTRAINT sync_log_pkey PRIMARY KEY (id);


--
-- Name: temporadas temporadas_codigo_key; Type: CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.temporadas
    ADD CONSTRAINT temporadas_codigo_key UNIQUE (codigo);


--
-- Name: temporadas temporadas_pkey; Type: CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.temporadas
    ADD CONSTRAINT temporadas_pkey PRIMARY KEY (id);


--
-- Name: usuarios usuarios_pkey; Type: CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.usuarios
    ADD CONSTRAINT usuarios_pkey PRIMARY KEY (id);


--
-- Name: usuarios usuarios_uuid_key; Type: CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.usuarios
    ADD CONSTRAINT usuarios_uuid_key UNIQUE (uuid);


--
-- Name: venta_rebajas venta_rebajas_pkey; Type: CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.venta_rebajas
    ADD CONSTRAINT venta_rebajas_pkey PRIMARY KEY (id);


--
-- Name: idx_categorias_ropa_activo; Type: INDEX; Schema: public; Owner: neondb_owner
--

CREATE INDEX idx_categorias_ropa_activo ON public.categorias_ropa USING btree (activo);


--
-- Name: idx_categorias_ropa_grupo; Type: INDEX; Schema: public; Owner: neondb_owner
--

CREATE INDEX idx_categorias_ropa_grupo ON public.categorias_ropa USING btree (grupo);


--
-- Name: idx_etiquetas_codigo; Type: INDEX; Schema: public; Owner: neondb_owner
--

CREATE INDEX idx_etiquetas_codigo ON public.etiquetas USING btree (codigo);


--
-- Name: idx_flujo_prenda_fecha; Type: INDEX; Schema: public; Owner: neondb_owner
--

CREATE INDEX idx_flujo_prenda_fecha ON public.flujo_prenda USING btree (fecha_movimiento);


--
-- Name: idx_flujo_prenda_producto; Type: INDEX; Schema: public; Owner: neondb_owner
--

CREATE INDEX idx_flujo_prenda_producto ON public.flujo_prenda USING btree (producto_id);


--
-- Name: idx_niveles_calidad_canal; Type: INDEX; Schema: public; Owner: neondb_owner
--

CREATE INDEX idx_niveles_calidad_canal ON public.niveles_calidad USING btree (canal_asignado);


--
-- Name: idx_precios_standard_producto; Type: INDEX; Schema: public; Owner: neondb_owner
--

CREATE INDEX idx_precios_standard_producto ON public.precios_standard USING btree (producto_id);


--
-- Name: idx_precios_standard_vigente; Type: INDEX; Schema: public; Owner: neondb_owner
--

CREATE INDEX idx_precios_standard_vigente ON public.precios_standard USING btree (vigente_desde, vigente_hasta);


--
-- Name: idx_productos_categoria; Type: INDEX; Schema: public; Owner: neondb_owner
--

CREATE INDEX idx_productos_categoria ON public.productos USING btree (categoria_feriaapp_id);


--
-- Name: idx_productos_categoria_revistete; Type: INDEX; Schema: public; Owner: neondb_owner
--

CREATE INDEX idx_productos_categoria_revistete ON public.productos USING btree (categoria_revistete_id);


--
-- Name: idx_productos_codigo; Type: INDEX; Schema: public; Owner: neondb_owner
--

CREATE INDEX idx_productos_codigo ON public.productos USING btree (codigo_barras);


--
-- Name: idx_productos_condicion; Type: INDEX; Schema: public; Owner: neondb_owner
--

CREATE INDEX idx_productos_condicion ON public.productos USING btree (condicion);


--
-- Name: idx_productos_estado; Type: INDEX; Schema: public; Owner: neondb_owner
--

CREATE INDEX idx_productos_estado ON public.productos USING btree (estado);


--
-- Name: idx_productos_etiqueta; Type: INDEX; Schema: public; Owner: neondb_owner
--

CREATE INDEX idx_productos_etiqueta ON public.productos USING btree (etiqueta_id);


--
-- Name: idx_productos_genero; Type: INDEX; Schema: public; Owner: neondb_owner
--

CREATE INDEX idx_productos_genero ON public.productos USING btree (genero_id);


--
-- Name: idx_productos_nivel_calidad; Type: INDEX; Schema: public; Owner: neondb_owner
--

CREATE INDEX idx_productos_nivel_calidad ON public.productos USING btree (nivel_calidad_id);


--
-- Name: idx_productos_segmento; Type: INDEX; Schema: public; Owner: neondb_owner
--

CREATE INDEX idx_productos_segmento ON public.productos USING btree (segmento_edad_id);


--
-- Name: idx_subcategorias_ropa_activo; Type: INDEX; Schema: public; Owner: neondb_owner
--

CREATE INDEX idx_subcategorias_ropa_activo ON public.subcategorias_ropa USING btree (activo);


--
-- Name: idx_subcategorias_ropa_categoria; Type: INDEX; Schema: public; Owner: neondb_owner
--

CREATE INDEX idx_subcategorias_ropa_categoria ON public.subcategorias_ropa USING btree (categoria_id);


--
-- Name: idx_venta_rebajas_linea; Type: INDEX; Schema: public; Owner: neondb_owner
--

CREATE INDEX idx_venta_rebajas_linea ON public.venta_rebajas USING btree (linea_venta_id);


--
-- Name: idx_venta_rebajas_venta; Type: INDEX; Schema: public; Owner: neondb_owner
--

CREATE INDEX idx_venta_rebajas_venta ON public.venta_rebajas USING btree (venta_id);


--
-- Name: productos trg_productos_updated_at; Type: TRIGGER; Schema: public; Owner: neondb_owner
--

CREATE TRIGGER trg_productos_updated_at BEFORE UPDATE ON public.productos FOR EACH ROW EXECUTE FUNCTION public.update_productos_updated_at();


--
-- Name: refresh_tokens trg_revocar_tokens_anteriores; Type: TRIGGER; Schema: public; Owner: neondb_owner
--

CREATE TRIGGER trg_revocar_tokens_anteriores AFTER INSERT ON public.refresh_tokens FOR EACH ROW EXECUTE FUNCTION public.revocar_tokens_anteriores();


--
-- Name: productos trg_temporada_inventario; Type: TRIGGER; Schema: public; Owner: neondb_owner
--

CREATE TRIGGER trg_temporada_inventario BEFORE UPDATE ON public.productos FOR EACH ROW EXECUTE FUNCTION public.incrementar_temporada_inventario();


--
-- Name: eventos_feria trg_validar_cierre_evento; Type: TRIGGER; Schema: public; Owner: neondb_owner
--

CREATE TRIGGER trg_validar_cierre_evento BEFORE UPDATE ON public.eventos_feria FOR EACH ROW EXECUTE FUNCTION public.validar_cierre_evento();


--
-- Name: categoria_canal categoria_canal_canal_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.categoria_canal
    ADD CONSTRAINT categoria_canal_canal_id_fkey FOREIGN KEY (canal_id) REFERENCES public.canales_venta(id) ON DELETE CASCADE;


--
-- Name: categoria_canal categoria_canal_categoria_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.categoria_canal
    ADD CONSTRAINT categoria_canal_categoria_id_fkey FOREIGN KEY (categoria_id) REFERENCES public.categorias_producto(id) ON DELETE CASCADE;


--
-- Name: clientes_frecuentes clientes_frecuentes_producto_preferido_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.clientes_frecuentes
    ADD CONSTRAINT clientes_frecuentes_producto_preferido_id_fkey FOREIGN KEY (producto_preferido_id) REFERENCES public.productos(id);


--
-- Name: deudas_diferidas deudas_diferidas_cliente_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.deudas_diferidas
    ADD CONSTRAINT deudas_diferidas_cliente_id_fkey FOREIGN KEY (cliente_id) REFERENCES public.clientes_frecuentes(id);


--
-- Name: dispositivos dispositivos_usuario_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.dispositivos
    ADD CONSTRAINT dispositivos_usuario_id_fkey FOREIGN KEY (usuario_id) REFERENCES public.usuarios(id) ON DELETE CASCADE;


--
-- Name: donaciones donaciones_recibido_por_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.donaciones
    ADD CONSTRAINT donaciones_recibido_por_id_fkey FOREIGN KEY (recibido_por_id) REFERENCES public.usuarios(id);


--
-- Name: etiquetas etiquetas_producto_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.etiquetas
    ADD CONSTRAINT etiquetas_producto_id_fkey FOREIGN KEY (producto_id) REFERENCES public.productos(id) ON DELETE CASCADE;


--
-- Name: eventos_feria eventos_feria_canal_venta_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.eventos_feria
    ADD CONSTRAINT eventos_feria_canal_venta_id_fkey FOREIGN KEY (canal_venta_id) REFERENCES public.canales_venta(id);


--
-- Name: eventos_feria eventos_feria_revisado_por_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.eventos_feria
    ADD CONSTRAINT eventos_feria_revisado_por_id_fkey FOREIGN KEY (revisado_por_id) REFERENCES public.usuarios(id);


--
-- Name: eventos_feria eventos_feria_vendedor_principal_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.eventos_feria
    ADD CONSTRAINT eventos_feria_vendedor_principal_id_fkey FOREIGN KEY (vendedor_principal_id) REFERENCES public.usuarios(id);


--
-- Name: flujo_prenda flujo_prenda_evaluado_por_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.flujo_prenda
    ADD CONSTRAINT flujo_prenda_evaluado_por_id_fkey FOREIGN KEY (evaluado_por_id) REFERENCES public.usuarios(id);


--
-- Name: flujo_prenda flujo_prenda_nivel_calidad_destino_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.flujo_prenda
    ADD CONSTRAINT flujo_prenda_nivel_calidad_destino_id_fkey FOREIGN KEY (nivel_calidad_destino_id) REFERENCES public.niveles_calidad(id);


--
-- Name: flujo_prenda flujo_prenda_nivel_calidad_origen_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.flujo_prenda
    ADD CONSTRAINT flujo_prenda_nivel_calidad_origen_id_fkey FOREIGN KEY (nivel_calidad_origen_id) REFERENCES public.niveles_calidad(id);


--
-- Name: flujo_prenda flujo_prenda_producto_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.flujo_prenda
    ADD CONSTRAINT flujo_prenda_producto_id_fkey FOREIGN KEY (producto_id) REFERENCES public.productos(id) ON DELETE CASCADE;


--
-- Name: items_donacion items_donacion_categoria_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.items_donacion
    ADD CONSTRAINT items_donacion_categoria_id_fkey FOREIGN KEY (categoria_id) REFERENCES public.categorias_producto(id);


--
-- Name: items_donacion items_donacion_clasificado_por_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.items_donacion
    ADD CONSTRAINT items_donacion_clasificado_por_id_fkey FOREIGN KEY (clasificado_por_id) REFERENCES public.usuarios(id);


--
-- Name: items_donacion items_donacion_donacion_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.items_donacion
    ADD CONSTRAINT items_donacion_donacion_id_fkey FOREIGN KEY (donacion_id) REFERENCES public.donaciones(id) ON DELETE CASCADE;


--
-- Name: items_donacion items_donacion_vendido_en_evento_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.items_donacion
    ADD CONSTRAINT items_donacion_vendido_en_evento_id_fkey FOREIGN KEY (vendido_en_evento_id) REFERENCES public.eventos_feria(id);


--
-- Name: journal_egresos journal_egresos_dispositivo_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.journal_egresos
    ADD CONSTRAINT journal_egresos_dispositivo_id_fkey FOREIGN KEY (dispositivo_id) REFERENCES public.dispositivos(id);


--
-- Name: journal_egresos journal_egresos_producto_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.journal_egresos
    ADD CONSTRAINT journal_egresos_producto_id_fkey FOREIGN KEY (producto_id) REFERENCES public.productos(id);


--
-- Name: journal_egresos journal_egresos_usuario_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.journal_egresos
    ADD CONSTRAINT journal_egresos_usuario_id_fkey FOREIGN KEY (usuario_id) REFERENCES public.usuarios(id);


--
-- Name: journal_insumos journal_insumos_dispositivo_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.journal_insumos
    ADD CONSTRAINT journal_insumos_dispositivo_id_fkey FOREIGN KEY (dispositivo_id) REFERENCES public.dispositivos(id);


--
-- Name: journal_insumos journal_insumos_usuario_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.journal_insumos
    ADD CONSTRAINT journal_insumos_usuario_id_fkey FOREIGN KEY (usuario_id) REFERENCES public.usuarios(id);


--
-- Name: journal_ventas journal_ventas_aprobado_por_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.journal_ventas
    ADD CONSTRAINT journal_ventas_aprobado_por_id_fkey FOREIGN KEY (aprobado_por_id) REFERENCES public.usuarios(id);


--
-- Name: journal_ventas journal_ventas_cliente_frecuente_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.journal_ventas
    ADD CONSTRAINT journal_ventas_cliente_frecuente_id_fkey FOREIGN KEY (cliente_frecuente_id) REFERENCES public.clientes_frecuentes(id);


--
-- Name: journal_ventas journal_ventas_dispositivo_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.journal_ventas
    ADD CONSTRAINT journal_ventas_dispositivo_id_fkey FOREIGN KEY (dispositivo_id) REFERENCES public.dispositivos(id);


--
-- Name: journal_ventas journal_ventas_evento_feria_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.journal_ventas
    ADD CONSTRAINT journal_ventas_evento_feria_id_fkey FOREIGN KEY (evento_feria_id) REFERENCES public.eventos_feria(id);


--
-- Name: journal_ventas journal_ventas_producto_ancla_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.journal_ventas
    ADD CONSTRAINT journal_ventas_producto_ancla_id_fkey FOREIGN KEY (producto_ancla_id) REFERENCES public.productos(id);


--
-- Name: journal_ventas journal_ventas_usuario_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.journal_ventas
    ADD CONSTRAINT journal_ventas_usuario_id_fkey FOREIGN KEY (usuario_id) REFERENCES public.usuarios(id);


--
-- Name: lineas_venta lineas_venta_producto_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.lineas_venta
    ADD CONSTRAINT lineas_venta_producto_id_fkey FOREIGN KEY (producto_id) REFERENCES public.productos(id);


--
-- Name: lineas_venta lineas_venta_venta_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.lineas_venta
    ADD CONSTRAINT lineas_venta_venta_id_fkey FOREIGN KEY (venta_id) REFERENCES public.journal_ventas(id) ON DELETE CASCADE;


--
-- Name: precios_standard precios_standard_producto_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.precios_standard
    ADD CONSTRAINT precios_standard_producto_id_fkey FOREIGN KEY (producto_id) REFERENCES public.productos(id);


--
-- Name: productos productos_categoria_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.productos
    ADD CONSTRAINT productos_categoria_id_fkey FOREIGN KEY (categoria_feriaapp_id) REFERENCES public.categorias_producto(id);


--
-- Name: productos productos_categoria_revistete_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.productos
    ADD CONSTRAINT productos_categoria_revistete_id_fkey FOREIGN KEY (categoria_revistete_id) REFERENCES public.categorias_ropa(id);


--
-- Name: productos productos_evaluado_por_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.productos
    ADD CONSTRAINT productos_evaluado_por_id_fkey FOREIGN KEY (evaluado_por_id) REFERENCES public.usuarios(id);


--
-- Name: productos productos_genero_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.productos
    ADD CONSTRAINT productos_genero_id_fkey FOREIGN KEY (genero_id) REFERENCES public.generos(id);


--
-- Name: productos productos_nivel_calidad_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.productos
    ADD CONSTRAINT productos_nivel_calidad_id_fkey FOREIGN KEY (nivel_calidad_id) REFERENCES public.niveles_calidad(id);


--
-- Name: productos productos_segmento_edad_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.productos
    ADD CONSTRAINT productos_segmento_edad_id_fkey FOREIGN KEY (segmento_edad_id) REFERENCES public.segmentos_edad(id);


--
-- Name: productos productos_subcategoria_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.productos
    ADD CONSTRAINT productos_subcategoria_id_fkey FOREIGN KEY (subcategoria_feriaapp_id) REFERENCES public.subcategorias_producto(id);


--
-- Name: productos productos_subcategoria_revistete_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.productos
    ADD CONSTRAINT productos_subcategoria_revistete_id_fkey FOREIGN KEY (subcategoria_revistete_id) REFERENCES public.subcategorias_ropa(id);


--
-- Name: productos productos_temporada_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.productos
    ADD CONSTRAINT productos_temporada_id_fkey FOREIGN KEY (temporada_id) REFERENCES public.temporadas(id);


--
-- Name: reclasificacion_log reclasificacion_log_venta_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.reclasificacion_log
    ADD CONSTRAINT reclasificacion_log_venta_id_fkey FOREIGN KEY (venta_id) REFERENCES public.journal_ventas(id);


--
-- Name: refresh_tokens refresh_tokens_dispositivo_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.refresh_tokens
    ADD CONSTRAINT refresh_tokens_dispositivo_id_fkey FOREIGN KEY (dispositivo_id) REFERENCES public.dispositivos(id) ON DELETE CASCADE;


--
-- Name: subcategorias_producto subcategorias_producto_categoria_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.subcategorias_producto
    ADD CONSTRAINT subcategorias_producto_categoria_id_fkey FOREIGN KEY (categoria_id) REFERENCES public.categorias_producto(id) ON DELETE CASCADE;


--
-- Name: subcategorias_ropa subcategorias_ropa_categoria_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.subcategorias_ropa
    ADD CONSTRAINT subcategorias_ropa_categoria_id_fkey FOREIGN KEY (categoria_id) REFERENCES public.categorias_ropa(id) ON DELETE CASCADE;


--
-- Name: sync_log sync_log_dispositivo_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.sync_log
    ADD CONSTRAINT sync_log_dispositivo_id_fkey FOREIGN KEY (dispositivo_id) REFERENCES public.dispositivos(id);


--
-- Name: sync_log sync_log_usuario_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.sync_log
    ADD CONSTRAINT sync_log_usuario_id_fkey FOREIGN KEY (usuario_id) REFERENCES public.usuarios(id);


--
-- Name: venta_rebajas venta_rebajas_aprobado_por_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.venta_rebajas
    ADD CONSTRAINT venta_rebajas_aprobado_por_id_fkey FOREIGN KEY (aprobado_por_id) REFERENCES public.usuarios(id);


--
-- Name: venta_rebajas venta_rebajas_linea_venta_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.venta_rebajas
    ADD CONSTRAINT venta_rebajas_linea_venta_id_fkey FOREIGN KEY (linea_venta_id) REFERENCES public.lineas_venta(id);


--
-- Name: venta_rebajas venta_rebajas_venta_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.venta_rebajas
    ADD CONSTRAINT venta_rebajas_venta_id_fkey FOREIGN KEY (venta_id) REFERENCES public.journal_ventas(id) ON DELETE CASCADE;


--
-- Name: DEFAULT PRIVILEGES FOR SEQUENCES; Type: DEFAULT ACL; Schema: public; Owner: cloud_admin
--

ALTER DEFAULT PRIVILEGES FOR ROLE cloud_admin IN SCHEMA public GRANT ALL ON SEQUENCES TO neon_superuser WITH GRANT OPTION;


--
-- Name: DEFAULT PRIVILEGES FOR TABLES; Type: DEFAULT ACL; Schema: public; Owner: cloud_admin
--

ALTER DEFAULT PRIVILEGES FOR ROLE cloud_admin IN SCHEMA public GRANT ALL ON TABLES TO neon_superuser WITH GRANT OPTION;


--
-- PostgreSQL database dump complete
--

\unrestrict 7psm3cgXQJL69hUfCU4dyVaTroj31nCNrGJyOHf6JWZKPw5dUh37MvlwgLoV7Zj

