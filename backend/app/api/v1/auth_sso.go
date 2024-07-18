package v1

import (
	"github.com/1Panel-dev/1Panel/backend/app/api/v1/helper"
	"github.com/1Panel-dev/1Panel/backend/constant"
	"github.com/1Panel-dev/1Panel/backend/utils/jwt"
	"github.com/gin-gonic/gin"
)

// SsoLogin @Tags Auth
// @Summary User login
// @Description 单点用户登录
// @Accept json
// @Param EntranceCode header string true "安全入口 base64 加密串"
// @Param request body dto.Login true "request"
// @Success 200 {object} dto.UserLoginInfo
// @Router /auth/login [post]
func (b *BaseApi) SsoLogin(c *gin.Context) {
	token := c.DefaultQuery("token", "")
	if token == "" {
		helper.ErrorWithDetail(c, constant.CodeErrInternalServer, constant.ErrTypeInternalServer, constant.ErrTokenParse)
		return
	}
	j := jwt.NewJWT()
	claims, err := j.ParseToken(token)
	if err != nil {
		helper.ErrorWithDetail(c, constant.CodeErrInternalServer, constant.ErrTypeInternalServer, err)
		return
	}
	user, err := authService.GenerateSession(c, claims.Name, constant.AuthMethodSession)
	go saveLoginLogs(c, err)
	if err != nil {
		helper.ErrorWithDetail(c, constant.CodeErrInternalServer, constant.ErrTypeInternalServer, err)
		return
	}
	helper.SuccessWithData(c, user)
}
