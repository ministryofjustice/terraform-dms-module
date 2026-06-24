locals {
  source_engine_configs = {
    oracle = {
      stream_position_column                = "SCN"
      password_keys                         = ["oracle_password", "asm_password"]
      password_delimiter                    = ","
      default_source_extra_connection_attrs = null
      supports_source_rds_slot_alarms       = false
    }
    postgres = {
      stream_position_column                = "STREAM_POSITION"
      password_keys                         = ["password"]
      password_delimiter                    = ","
      default_source_extra_connection_attrs = "PluginName=test_decoding;CaptureDDLs=N;HeartbeatEnable=true;HeartbeatFrequency=5;HeartbeatSchema=public;"
      supports_source_rds_slot_alarms       = true
    }
  }

  selected_source_engine = local.source_engine_configs[var.dms_source.engine_name]

  source_engine_password = join(
    local.selected_source_engine.password_delimiter,
    [for k in local.selected_source_engine.password_keys : local.database_credentials[k]]
  )

  source_engine_config = {
    stream_position_column                = local.selected_source_engine.stream_position_column
    password                              = local.source_engine_password
    default_source_extra_connection_attrs = local.selected_source_engine.default_source_extra_connection_attrs
    supports_source_rds_slot_alarms       = local.selected_source_engine.supports_source_rds_slot_alarms
  }

  source_extra_connection_attributes = (
    var.dms_source.extra_connection_attributes != null
    ? var.dms_source.extra_connection_attributes
    : local.source_engine_config.default_source_extra_connection_attrs
  )
}
