# Backend Missing Feature Design

这个目录汇总了 `groupmembers'markdown/backend_incomplete_review.json` 中未完成能力的设计产物，覆盖以下范围：

- 上传入口前置校验
- Outfit 持久化与缩略图生成
- Creator Profile / Creator Item / Card Pack 能力
- Card Pack 导入、导入历史与 provenance 追踪
- Virtual Wardrobe 自动创建与系统托管约束

产物说明：

- `NAMING_CONVENTIONS.md`
  定义数据库、API、代码的统一命名规范，确保字段命名和状态值的一致性。
- `feature_flow.html`
  覆盖创作者发布、消费者导入、上传校验与搭配保存的整体流程图。
- `feature_architecture.html`
  覆盖 API、服务、数据层、异步任务和对象存储的架构图。
- `api_interface_design.md`
  覆盖数据模型扩展、接口设计、权限边界、状态机与推荐实现顺序。
- `unified_role_ui_design.md`
  覆盖"普通用户与发布者共用同一界面"的产品结构、能力分层、导航建议与后端配套调整。
- `unified_role_frontend_ia.md`
  覆盖统一界面的前端信息架构、页面入口、能力可见性和推荐的 `GET /me` capability 字段。
- `backend_implementation_draft.md`
  覆盖更接近实现的后端草案：文件清单、模型骨架、schema 草案、路由签名、事务流程与 Alembic 落地顺序。

建议阅读顺序：

0. 先看 `NAMING_CONVENTIONS.md`，了解命名规范和一致性要求。
1. 再看 `feature_flow.html`，确认整体业务闭环。
2. 然后看 `feature_architecture.html`，确认后端模块拆分和依赖关系。
3. 接着看 `api_interface_design.md`，作为后续建模和接口落地的基线。
4. 若要推进单界面多身份方案，再看 `unified_role_ui_design.md`。
5. 若要继续细化前端落地，再看 `unified_role_frontend_ia.md`。
6. 若要开始后端实现，再看 `backend_implementation_draft.md`。
